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

  # Idempotence (#124) : le JS rappelle create_payment_intent à chaque turbo:load.
  # On ne doit pas accumuler une commande pending par visite.
  context 'idempotence — réutilisation de la commande pending' do
    before { stub_stripe_payment_intent_create(amount: 550) }

    it 'ne crée pas de doublon et réutilise le même PI quand le panier est identique' do
      create_payment_intent
      order = Order.order(:created_at).last
      pi_id = order.payment_intent_id

      stub_stripe_payment_intent_retrieve(id: pi_id, status: 'requires_payment_method', amount: 550)
      allow(Stripe::PaymentIntent).to receive(:update)

      expect { create_payment_intent }.not_to change { Order.where(status: :pending).count }
      expect(Order.where(customer: customer, bake_day: bake_day, status: :pending).count).to eq(1)
      expect(Stripe::PaymentIntent).not_to have_received(:update)
      expect(JSON.parse(response.body)['payment_intent_id']).to eq(pi_id)
    end

    it 'met à jour la commande pending et le montant du PI quand le panier change' do
      create_payment_intent
      order = Order.order(:created_at).last
      pi_id = order.payment_intent_id

      # Le panier passe à 2 unités (1100 cents).
      post '/cart/add', params: { product_variant_id: variant.id, bake_day_id: bake_day.id, quantity: 1 }

      stub_stripe_payment_intent_retrieve(id: pi_id, status: 'requires_payment_method', amount: 550)
      stub_stripe_payment_intent_update(id: pi_id, amount: 1100)

      expect { create_payment_intent }.not_to change(Order, :count)
      order.reload
      expect(order.total_cents).to eq(1100)
      expect(order.order_items.sum(:qty)).to eq(2)
      expect(Stripe::PaymentIntent).to have_received(:update).with(pi_id, hash_including(amount: 1100))
    end

    it 'ne réutilise pas et ne crée pas de doublon quand le PI est déjà succeeded (paiement vivant)' do
      create_payment_intent
      order = Order.order(:created_at).last
      pi_id = order.payment_intent_id

      stub_stripe_payment_intent_retrieve(id: pi_id, status: 'succeeded', amount: 550)
      allow(Stripe::PaymentIntent).to receive(:update)

      expect { create_payment_intent }.not_to change(Order, :count)
      expect(Stripe::PaymentIntent).not_to have_received(:update)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['payment_intent_id']).to eq(pi_id)
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

  # Le tunnel en ligne était muet sur Sentry : ces échecs ne faisaient qu'un
  # render JSON. On vérifie qu'ils sont désormais remontés avec un contexte.
  describe 'remontée Sentry des échecs du tunnel en ligne' do
    it 'trace un rejet de capacité (order_creation_rejected) et répond 422' do
      allow_any_instance_of(BakeCapacityService)
        .to receive(:cart_fits?).and_return({ fits: false, errors: [ 'Four : capacité dépassée' ] })
      expect_any_instance_of(CheckoutController)
        .to receive(:capture_checkout_issue).with('order_creation_rejected', hash_including(:level, :extra)).and_call_original

      create_payment_intent
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'trace un échec Stripe (stripe_payment_intent_failed)' do
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(Stripe::StripeError.new('card_declined'))
      expect_any_instance_of(CheckoutController)
        .to receive(:capture_checkout_issue).with('stripe_payment_intent_failed', hash_including(:exception)).and_call_original

      create_payment_intent
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'répond 422 tracé (et non plus 500 muet) quand le jour de cuisson a disparu' do
      bake_day.destroy
      expect_any_instance_of(CheckoutController)
        .to receive(:capture_checkout_issue).with('bake_day_missing', hash_including(:level)).and_call_original

      create_payment_intent
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /checkout/new — méthode de paiement (#36)' do
    it 'ne propose pas l\'option cash par défaut (paiement en ligne uniquement)' do
      get '/checkout/new'

      expect(response).to have_http_status(:ok)

      online_radio = response.body[%r{<input[^>]*value="online"[^>]*>}]
      cash_radio = response.body[%r{<input[^>]*value="cash"[^>]*>}]

      expect(online_radio).to include('checked')
      expect(cash_radio).to be_nil
    end

    context 'pour un client autorisé au paiement cash' do
      let(:customer) { create(:customer, first_name: 'Léa', cash_payment_allowed: true) }

      it 'propose l\'option « payer en liquide »' do
        get '/checkout/new'

        expect(response).to have_http_status(:ok)
        expect(response.body[%r{<input[^>]*value="cash"[^>]*>}]).to be_present
      end
    end
  end

  describe 'POST /checkout/create_cash_order (#36)' do
    def create_cash_order(body = { first_name: 'Léa' })
      post '/checkout/create_cash_order', params: body.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }
    end

    it 'refuse la commande sans paiement en ligne pour un client non autorisé' do
      expect { create_cash_order }.not_to change(Order, :count)
      expect(response).to have_http_status(:forbidden)
    end

    context 'pour un client autorisé au paiement cash' do
      let(:customer) { create(:customer, first_name: 'Léa', cash_payment_allowed: true) }

      it 'crée une commande unpaid' do
        expect { create_cash_order }.to change { Order.where(status: :unpaid).count }.by(1)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
