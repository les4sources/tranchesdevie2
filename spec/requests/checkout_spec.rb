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

  describe 'GET /checkout/new — affichage de l\'option portefeuille' do
    it 'affiche le radio + le bouton portefeuille quand le solde couvre le total' do
      create(:wallet, customer: customer, balance_cents: 5_000)
      get '/checkout/new'
      expect(response.body).to include('value="wallet"')
      # id="…" cible l'élément bouton rendu (la chaîne 'submit-wallet-order' est
      # aussi présente dans le JS inline, indépendamment de l'affichage du bouton).
      expect(response.body).to include('id="submit-wallet-order"')
      expect(response.body).to include('Payer avec mon portefeuille')
    end

    it 'n\'affiche pas l\'option portefeuille quand le solde est insuffisant' do
      create(:wallet, customer: customer, balance_cents: 100)
      get '/checkout/new'
      expect(response.body).not_to include('value="wallet"')
      expect(response.body).not_to include('id="submit-wallet-order"')
    end

    it 'n\'affiche pas l\'option quand le client n\'a pas de portefeuille' do
      get '/checkout/new'
      expect(response.body).not_to include('value="wallet"')
    end
  end

  describe 'POST /checkout/create_wallet_order (paiement portefeuille)' do
    def create_wallet_order(body = { first_name: 'Léa', last_name: 'Boulanger' })
      post '/checkout/create_wallet_order', params: body.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }
    end

    context 'quand le solde disponible couvre le total' do
      let!(:wallet) { create(:wallet, customer: customer, balance_cents: 5_000) }

      it 'crée une commande payée et la débite du portefeuille' do
        expect { create_wallet_order }.to change { Order.where(status: :paid, source: :checkout).count }.by(1)
        expect(response).to have_http_status(:ok)

        body = JSON.parse(response.body)
        expect(body['success']).to be(true)
        expect(body['order_token']).to be_present

        order = Order.find_by(public_token: body['order_token'])
        expect(order.payment_method).to eq(:wallet)
        expect(wallet.reload.balance_cents).to eq(5_000 - order.total_cents)
      end

      it 'envoie la confirmation email comme le paiement en ligne' do
        expect(OrderNotificationService).to receive(:send_confirmation)
        create_wallet_order
      end
    end

    context 'quand le solde est insuffisant' do
      let!(:wallet) { create(:wallet, customer: customer, balance_cents: 100) }

      it 'ne crée aucune commande persistée et renvoie 422' do
        expect { create_wallet_order }.not_to change(Order, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(wallet.reload.balance_cents).to eq(100)
      end
    end

    context 'quand le client n\'a pas de portefeuille' do
      it 'renvoie 422 sans créer de commande' do
        expect { create_wallet_order }.not_to change(Order, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'idempotence (double soumission)' do
      let!(:wallet) { create(:wallet, customer: customer, balance_cents: 5_000) }

      it 'une 2e soumission ne recrée pas de commande ni ne re-débite' do
        create_wallet_order
        first_token = JSON.parse(response.body)['order_token']
        balance_after_first = wallet.reload.balance_cents

        # La 2e requête simule un onglet concurrent : on remet le panier en session
        # (le succès de la 1re l'a vidé) pour rejouer la soumission telle quelle.
        post '/cart/add', params: { product_variant_id: variant.id, bake_day_id: bake_day.id, quantity: 1 }

        expect { create_wallet_order }.not_to change { Order.where(status: :paid).count }
        expect(JSON.parse(response.body)['order_token']).to eq(first_token)
        expect(wallet.reload.balance_cents).to eq(balance_after_first)
      end
    end
  end
end
