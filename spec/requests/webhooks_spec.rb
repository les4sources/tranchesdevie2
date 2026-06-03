require 'rails_helper'

# Stripe webhook → order creation + idempotency. Covers ISC-18/19.
# `Stripe::Webhook.construct_event` is stubbed so payload/signature are irrelevant;
# we drive the controller with a fabricated event object.
RSpec.describe 'Stripe webhook', type: :request do
  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
    # Cut-off acceptance is exercised elsewhere (capacity/bake-day specs); here we
    # isolate the webhook's order-creation wiring.
    allow(BakeDayService).to receive(:can_order_for?).and_return(true)
  end

  let(:bake_day) { create(:bake_day, :can_order) }
  let!(:product) { create(:product, channel: 'store') }
  let!(:variant) { create(:product_variant, product: product, channel: 'store') }
  let(:customer) { create(:customer) }
  let(:pi_id) { "pi_test_#{SecureRandom.hex(6)}" }

  def succeeded_metadata
    {
      'customer_id' => customer.id.to_s,
      'bake_day_id' => bake_day.id.to_s,
      'cart_items' => [ { 'product_variant_id' => variant.id, 'qty' => 1 } ].to_json
    }
  end

  def fabricate_event(type:, metadata:)
    pi = double('Stripe::PaymentIntent', id: pi_id, metadata: metadata)
    double('Stripe::Event', id: "evt_#{SecureRandom.hex(6)}", type: type,
                            data: double('event_data', object: pi))
  end

  def deliver(event)
    allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
    post '/webhooks/stripe', params: '{}', headers: { 'HTTP_STRIPE_SIGNATURE' => 't=1,v1=sig' }
  end

  describe 'payment_intent.succeeded (ISC-18)' do
    it 'creates a paid order from the payment intent metadata' do
      event = fabricate_event(type: 'payment_intent.succeeded', metadata: succeeded_metadata)
      expect { deliver(event) }
        .to change { Order.where(payment_intent_id: pi_id).count }.from(0).to(1)
      expect(Order.find_by(payment_intent_id: pi_id).status).to eq('paid')
    end

    it 'records the payment date on the order' do
      event = fabricate_event(type: 'payment_intent.succeeded', metadata: succeeded_metadata)
      deliver(event)

      expect(Order.find_by(payment_intent_id: pi_id).read_attribute(:paid_at)).to be_present
    end
  end

  describe 'idempotency on event id (ISC-19)' do
    it 'ignores a re-delivered event and does not create a second order' do
      event = fabricate_event(type: 'payment_intent.succeeded', metadata: succeeded_metadata)
      deliver(event)
      expect(Order.where(payment_intent_id: pi_id).count).to eq(1)

      # Same event.id re-delivered → StripeEvent dedup short-circuits.
      expect { deliver(event) }
        .not_to change { Order.where(payment_intent_id: pi_id).count }
    end
  end
end
