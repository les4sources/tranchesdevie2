require 'rails_helper'

# #135 (Sentry TRANCHESDEVIE-G/H) : un nouveau client (OTP vérifié, sans compte)
# ne doit jamais faire remonter un RecordInvalid muet quand le prénom arrive vide.
# La création du PaymentIntent est refusée proprement (422 ciblé) et le parcours
# nominal (prénom rempli) reste inchangé.
RSpec.describe 'Checkout — prénom obligatoire pour un nouveau client', type: :request do
  let(:bake_day) { create(:bake_day, :can_order) }
  let!(:product) { create(:product, channel: 'store') }
  let!(:variant) { create(:product_variant, product: product, channel: 'store', price_cents: 550) }
  let(:new_phone) { '+32470111222' }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)

    # OTP vérifié pour un numéro SANS compte client : le flux checkout laisse
    # session[:customer_id] à nil tant que le prénom n'est pas fourni.
    allow(OtpService).to receive(:send_otp).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_otp).and_return({ success: true })

    post '/cart/add', params: { product_variant_id: variant.id, bake_day_id: bake_day.id, quantity: 1 }
    post '/checkout/verify_phone', params: { phone_e164: new_phone }
    post '/checkout/verify_otp', params: { code: '123456' } # sans first_name : aucun client créé
  end

  def create_payment_intent(body)
    post '/checkout/create_payment_intent', params: body.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }
  end

  it 'part bien d\'un nouveau client sans compte' do
    expect(Customer.find_by(phone_e164: new_phone)).to be_nil
  end

  context 'quand le prénom est vide' do
    it 'répond 422 ciblé, ne crée ni client ni commande, sans RecordInvalid' do
      expect(Stripe::PaymentIntent).not_to receive(:create)

      expect do
        create_payment_intent(first_name: '')
      end.to change(Order, :count).by(0).and change(Customer, :count).by(0)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body['field']).to eq('first_name')
      expect(body['error']).to include('prénom')
    end

    it 'ne remonte aucune erreur (RecordInvalid) vers Sentry' do
      expect_any_instance_of(CheckoutController)
        .not_to receive(:capture_checkout_issue)

      create_payment_intent(first_name: '')
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  context 'quand le prénom ne contient que des espaces' do
    it 'est traité comme vide (422 ciblé, aucun client créé)' do
      expect do
        create_payment_intent(first_name: '   ')
      end.to change(Order, :count).by(0).and change(Customer, :count).by(0)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['field']).to eq('first_name')
    end
  end

  context 'quand le prénom est rempli (parcours nominal)' do
    before { stub_stripe_payment_intent_create(amount: 550) }

    it 'crée le client et réserve une commande pending avec un PaymentIntent' do
      expect do
        create_payment_intent(first_name: '  Léa  ')
      end.to change { Order.where(status: :pending).count }.by(1)
        .and change(Customer, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include('client_secret', 'payment_intent_id')

      customer = Customer.find_by(phone_e164: new_phone)
      expect(customer.first_name).to eq('Léa') # espaces retirés
    end
  end
end
