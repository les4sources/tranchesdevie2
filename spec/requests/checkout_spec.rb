require 'rails_helper'

# Réservation de capacité au paiement : la commande online est créée (pending)
# AVANT le PaymentIntent, sous contrôle de capacité.
RSpec.describe 'Checkout — réservation au paiement', type: :request do
  let(:bake_day) { create(:bake_day, :can_order) }
  let!(:product) { create(:product, channel: 'store') }
  let!(:variant) { create(:product_variant, product: product, channel: 'store', price_cents: 550) }
  let(:customer) { create(:customer, first_name: 'Léa') }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)

    # Authentifier le client (stub OTP) puis garnir le panier.
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })
    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }

    post '/cart/add', params: { product_variant_id: variant.id, bake_day_id: bake_day.id, quantity: 1 }
  end

  def create_payment_intent(body = { first_name: 'Léa' })
    post '/checkout/create_payment_intent', params: body.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }
  end

  context 'when capacity is available' do
    before { stub_stripe_payment_intent_create(amount: 550) }

    it 'reserves a pending order before taking payment' do
      expect { create_payment_intent }.to change { Order.where(status: :pending).count }.by(1)

      order = Order.order(:created_at).last
      expect(order.status).to eq('pending')
      expect(order.source).to eq('checkout')
      expect(order.payment_intent_id).to be_present
      expect(order.customer).to eq(customer)
      expect(order.bake_day).to eq(bake_day)
    end

    it 'returns the client secret' do
      create_payment_intent
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include('client_secret', 'payment_intent_id')
    end
  end

  context 'when the bake day is full' do
    before do
      allow_any_instance_of(BakeCapacityService)
        .to receive(:cart_fits?).and_return({ fits: false, errors: [ 'Four : capacité dépassée' ] })
    end

    it 'does not create an order and does not call Stripe' do
      expect(Stripe::PaymentIntent).not_to receive(:create)
      expect { create_payment_intent }.not_to change(Order, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  context 'when Stripe rejects the PaymentIntent' do
    before do
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(Stripe::StripeError.new('card_declined'))
    end

    it 'rolls back the reservation (no orphan pending order)' do
      expect { create_payment_intent }.not_to change(Order, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
