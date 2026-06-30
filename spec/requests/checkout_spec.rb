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
    allow(SmsService).to receive(:send_confirmation)

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

  describe 'Client facturable (#122)' do
    describe 'GET /checkout/new' do
      context 'pour un client non facturable' do
        it 'n\'affiche pas le callout facture et garde le sélecteur de paiement' do
          get '/checkout/new'

          expect(response).to have_http_status(:ok)
          expect(response.body).not_to include('id="submit-invoice-order"')
          expect(response.body[%r{<input[^>]*value="online"[^>]*>}]).to include('checked')
        end
      end

      context 'pour un client facturable' do
        let(:customer) { create(:customer, first_name: 'Léa', billable: true) }

        it 'affiche le callout facture + bouton de confirmation, sans sélecteur de paiement' do
          get '/checkout/new'

          expect(response).to have_http_status(:ok)
          expect(response.body).to include('id="submit-invoice-order"')
          expect(response.body).to include('facture')
          # Aucun sélecteur de paiement (radios) ni Payment Element Stripe visible.
          expect(response.body[%r{<input[^>]*name="payment_method"[^>]*>}]).to be_nil
          expect(response.body).not_to include('id="submit-cash-order"')
        end
      end

      context 'pour un client à la fois facturable et autorisé au cash' do
        let(:customer) { create(:customer, first_name: 'Léa', billable: true, cash_payment_allowed: true) }

        it 'fait primer le flux facturable (pas d\'option cash)' do
          get '/checkout/new'

          expect(response).to have_http_status(:ok)
          expect(response.body).to include('id="submit-invoice-order"')
          expect(response.body).not_to include('id="submit-cash-order"')
          expect(response.body[%r{<input[^>]*value="cash"[^>]*>}]).to be_nil
        end
      end
    end

    describe 'POST /checkout/create_invoice_order' do
      def create_invoice_order(body = { first_name: 'Léa' })
        post '/checkout/create_invoice_order', params: body.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      it 'refuse la commande facturable pour un client non facturable (403)' do
        expect { create_invoice_order }.not_to change(Order, :count)
        expect(response).to have_http_status(:forbidden)
      end

      context 'pour un client facturable' do
        let(:customer) { create(:customer, first_name: 'Léa', billable: true) }

        it 'crée une commande unpaid + requires_invoice et renvoie le token' do
          expect { create_invoice_order }.to change { Order.where(status: :unpaid, requires_invoice: true).count }.by(1)
          expect(response).to have_http_status(:ok)

          order = Order.order(:created_at).last
          expect(JSON.parse(response.body)['order_token']).to eq(order.public_token)
          expect(order.requires_invoice).to be(true)
        end

        it 'déclenche les notifications SMS et email' do
          expect(SmsService).to receive(:send_confirmation)
          expect(OrderNotificationService).to receive(:send_confirmation)

          create_invoice_order
        end
      end

      context 'pour un client facturable ET autorisé au cash' do
        let(:customer) { create(:customer, first_name: 'Léa', billable: true, cash_payment_allowed: true) }

        it 'crée une commande facturable (priorité facture sur cash)' do
          expect { create_invoice_order }.to change { Order.where(requires_invoice: true).count }.by(1)
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end
end
