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
end
