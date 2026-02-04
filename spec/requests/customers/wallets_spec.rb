require 'rails_helper'

RSpec.describe 'Customers::Wallets', type: :request do
  let(:customer) { create(:customer) }

  def authenticate_customer
    allow(OtpService).to receive(:send_otp).and_return({ success: true })
    allow(OtpService).to receive(:verify_otp).and_return({ success: true })

    post '/connexion', params: { phone_e164: customer.phone_e164 }
    post '/connexion', params: { phone_e164: customer.phone_e164, otp_code: '123456' }
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
        expect(json['client_secret']).to be_present
      end

      it 'uses Bancontact as payment method' do
        expect(Stripe::PaymentIntent).to receive(:create).with(
          hash_including(
            amount: 5000,
            currency: 'eur',
            payment_method_types: ['bancontact']
          )
        ).and_return(double(id: 'pi_123', client_secret: 'secret'))

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
        ).and_return(double(id: 'pi_123', client_secret: 'secret'))

        post '/customers/portefeuille/recharger', params: { amount_cents: 5000 }, as: :json
      end

      it 'rejects amounts below minimum' do
        post '/customers/portefeuille/recharger', params: { amount_cents: 400 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
