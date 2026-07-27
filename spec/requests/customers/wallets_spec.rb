require 'rails_helper'

RSpec.describe 'Customers::Wallets', type: :request do
  let(:customer) { create(:customer) }

  def authenticate_customer
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
  end

  describe 'GET /customers/portefeuille' do
    context 'when customer is authenticated' do
      before { authenticate_customer }

      it 'displays the wallet page' do
        get '/customers/portefeuille'
        expect(response).to have_http_status(:success)
      end

      it 'creates a wallet if none exists' do
        expect { get '/customers/portefeuille' }.to change { Wallet.count }.by(1)
      end

      it 'shows existing wallet' do
        wallet = create(:wallet, customer: customer, balance_cents: 5000)
        get '/customers/portefeuille'
        expect(response.body).to include('50')  # 50€
      end
    end

    context 'when customer is not authenticated' do
      it 'redirects to login' do
        get '/customers/portefeuille'
        expect(response).to redirect_to('/connexion')
      end
    end
  end

  describe 'GET /customers/portefeuille/recharger' do
    context 'when customer is authenticated' do
      before { authenticate_customer }

      it 'displays the reload form' do
        get '/customers/portefeuille/recharger'
        expect(response).to have_http_status(:success)
      end

      it 'shows the pedagogical banner about calendar credit' do
        get '/customers/portefeuille/recharger'
        expect(response.body).to include('À quoi sert ce crédit')
      end
    end
  end

  describe 'POST /customers/portefeuille/recharger' do
    context 'when customer is authenticated' do
      before { authenticate_customer }

      it 'creates a Stripe PaymentIntent' do
        stub_stripe_payment_intent_create(amount: 5000)

        post '/customers/portefeuille/recharger', params: { amount_cents: 5000 }, as: :json
        expect(response).to have_http_status(:success)

        json = JSON.parse(response.body)
        expect(json['redirect_url']).to be_present
      end

      it 'uses Bancontact as payment method' do
        expect(Stripe::PaymentIntent).to receive(:create).with(
          hash_including(
            amount: 5000,
            currency: 'eur',
            payment_method_types: [ 'bancontact' ]
          )
        ).and_return(double(id: 'pi_123', client_secret: 'secret', status: 'requires_payment_method'))

        post '/customers/portefeuille/recharger', params: { amount_cents: 5000 }, as: :json
      end

      it 'stores customer_id in metadata' do
        expect(Stripe::PaymentIntent).to receive(:create).with(
          hash_including(
            metadata: hash_including(
              customer_id: customer.id,
              type: 'wallet_reload'
            )
          )
        ).and_return(double(id: 'pi_123', client_secret: 'secret', status: 'requires_payment_method'))

        post '/customers/portefeuille/recharger', params: { amount_cents: 5000 }, as: :json
      end

      it 'rejects amounts below minimum' do
        post '/customers/portefeuille/recharger', params: { amount_cents: 400 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  # Page de retour Bancontact. Elle crédite le portefeuille, tout comme le
  # webhook Stripe : les deux ne doivent jamais créditer la même recharge (#159).
  describe 'GET /customers/portefeuille/success' do
    let!(:wallet) { create(:wallet, customer: customer, balance_cents: 1000) }
    let(:pi_id) { 'pi_reload_success_123' }

    before { authenticate_customer }

    def stub_succeeded_reload(amount: 5000, &during_retrieve)
      pi = double('Stripe::PaymentIntent', id: pi_id, status: 'succeeded', amount: amount,
                                           metadata: { 'type' => 'wallet_reload' })
      allow(Stripe::PaymentIntent).to receive(:retrieve).with(pi_id) do
        during_retrieve&.call
        pi
      end
    end

    it 'credits the wallet and displays the amount' do
      stub_succeeded_reload

      expect { get '/customers/portefeuille/success', params: { payment_intent: pi_id } }
        .to change { wallet.reload.balance_cents }.from(1000).to(6000)
      expect(response.body).to include('50')
    end

    it 'ne crédite pas une seconde fois quand la recharge est déjà encaissée' do
      wallet.credit!(5000, type: :top_up, stripe_payment_intent_id: pi_id)

      expect { get '/customers/portefeuille/success', params: { payment_intent: pi_id } }
        .not_to change { wallet.reload.balance_cents }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('50')
    end

    # Le webhook crédite pile entre le check d'idempotence du contrôleur et
    # l'appel à WalletService.top_up — c'est la course qui produisait le bug.
    it 'ne crédite pas deux fois quand le webhook gagne la course pendant la requête' do
      stub_succeeded_reload do
        WalletService.top_up(wallet: wallet, amount_cents: 5000, stripe_payment_intent_id: pi_id)
      end

      expect { get '/customers/portefeuille/success', params: { payment_intent: pi_id } }
        .to change { wallet.reload.balance_cents }.from(1000).to(6000)
      expect(WalletTransaction.where(stripe_payment_intent_id: pi_id).count).to eq(1)
      expect(response.body).to include('50')
    end
  end
end
