require 'rails_helper'

# Stripe webhook → encaissement de la commande déjà réservée + idempotence.
# La commande est créée au moment du paiement (create_payment_intent), pas par
# le webhook. Le webhook ne fait que l'encaisser (pending → paid).
# `Stripe::Webhook.construct_event` est stubbé ; on pilote le contrôleur avec un
# événement fabriqué.
RSpec.describe 'Stripe webhook', type: :request do
  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
  end

  # Bascule sur l'adapter ActiveJob `:test` uniquement pour les exemples qui
  # vérifient l'enfilement d'un job (matchers `have_enqueued_job`).
  around(:each, :active_job_test) do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  let(:bake_day) { create(:bake_day, :can_order) }
  let(:customer) { create(:customer) }
  let(:pi_id) { "pi_test_#{SecureRandom.hex(6)}" }

  # Réservation : commande online en attente, rattachée au PaymentIntent.
  let!(:order) do
    create(:order, :pending, :with_items, customer: customer, bake_day: bake_day, payment_intent_id: pi_id)
  end

  def fabricate_event(type:, metadata: {})
    pi = double('Stripe::PaymentIntent', id: pi_id, metadata: metadata)
    double('Stripe::Event', id: "evt_#{SecureRandom.hex(6)}", type: type,
                            data: double('event_data', object: pi))
  end

  def deliver(event)
    allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
    post '/webhooks/stripe', params: '{}', headers: { 'HTTP_STRIPE_SIGNATURE' => 't=1,v1=sig' }
  end

  describe 'payment_intent.succeeded' do
    it 'marks the reserved order as paid' do
      event = fabricate_event(type: 'payment_intent.succeeded')
      expect { deliver(event) }.to change { order.reload.status }.from('pending').to('paid')
    end

    it 'records the payment date and a payment record' do
      deliver(fabricate_event(type: 'payment_intent.succeeded'))

      expect(order.reload.read_attribute(:paid_at)).to be_present
      expect(order.payment).to be_present
      expect(order.payment.status).to eq('succeeded')
    end

    it 'never creates an order when none is reserved for the payment intent' do
      Order.where(payment_intent_id: pi_id).destroy_all
      event = fabricate_event(type: 'payment_intent.succeeded')

      expect { deliver(event) }.not_to change(Order, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'enqueues the Stripe fee retrieval for the new payment', :active_job_test do
      expect { deliver(fabricate_event(type: 'payment_intent.succeeded')) }
        .to have_enqueued_job(FetchStripeFeeJob)
    end
  end

  describe 'idempotency on event id' do
    it 'ignores a re-delivered event' do
      event = fabricate_event(type: 'payment_intent.succeeded')
      deliver(event)
      expect(order.reload.status).to eq('paid')

      # Même event.id re-livré → dédup StripeEvent court-circuite.
      expect { deliver(event) }.not_to change { Payment.count }
    end
  end

  describe 'refund failure (charge.refund.updated)' do
    def fabricate_refund_event(status:, failure_reason: 'expired_or_canceled_card')
      refund = double('Stripe::Refund', status: status, payment_intent: pi_id, failure_reason: failure_reason)
      double('Stripe::Event', id: "evt_#{SecureRandom.hex(6)}", type: 'charge.refund.updated',
                              data: double('event_data', object: refund))
    end

    before do
      # La commande a été annulée puis marquée « remboursée » par charge.refunded.
      order.update!(status: :cancelled)
      create(:payment, :refunded, order: order)
      allow(SlackService).to receive(:send_message)
    end

    it 're-marks the payment as collected when the refund fails' do
      deliver(fabricate_refund_event(status: 'failed'))
      expect(order.payment.reload.status).to eq('succeeded')
    end

    it 'keeps the order cancelled and alerts the admin' do
      expect(SlackService).to receive(:send_message).with(/Remboursement Stripe ÉCHOUÉ/)
      deliver(fabricate_refund_event(status: 'failed'))
      expect(order.reload.status).to eq('cancelled')
    end

    it 'ignores a refund update that did not fail' do
      deliver(fabricate_refund_event(status: 'succeeded'))
      expect(order.payment.reload.status).to eq('refunded')
    end
  end
end
