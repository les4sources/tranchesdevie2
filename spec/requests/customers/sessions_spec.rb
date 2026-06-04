require 'rails_helper'

RSpec.describe 'Customers::Sessions', type: :request do
  # Exercise the real controller -> OtpService -> PhoneVerification path, but
  # never hit the SMS gateway (stub the private transport to succeed).
  before { allow(OtpService).to receive(:send_otp_sms).and_return(true) }

  def last_code
    PhoneVerification.order(:created_at).last.code
  end

  describe 'login by phone (SMS channel)' do
    let(:phone) { "+32470111222" }

    it 'creates a verification and reports the SMS channel' do
      expect {
        post '/connexion', params: { identifier: phone }
      }.to change { PhoneVerification.where(phone_e164: phone).count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("par SMS")
    end

    it 'accepts a national format (0…) and normalizes to E.164' do
      post '/connexion', params: { identifier: "0470111222" }
      expect(PhoneVerification.last.phone_e164).to eq("+32470111222")
    end

    it 'signs in (find_or_create) once the code is verified' do
      create(:customer, phone_e164: phone, first_name: "Léa")
      post '/connexion', params: { identifier: phone }

      post '/connexion', params: { identifier: phone, otp_code: last_code }

      expect(response).to redirect_to(customers_account_path)
      follow_redirect!
      expect(response.body).to include("Connexion réussie")
    end
  end

  describe 'login by email (email channel)' do
    let(:phone) { "+32470333444" }

    it 'emails the code to a customer who has an email on file' do
      create(:customer, phone_e164: phone, email: "eater@example.com", first_name: "Sam")

      expect {
        post '/connexion', params: { identifier: "eater@example.com" }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("par e-mail")
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "eater@example.com" ])
    end

    it 'signs the customer in after verifying the emailed code' do
      customer = create(:customer, phone_e164: phone, email: "eater@example.com", first_name: "Sam")
      post '/connexion', params: { identifier: "eater@example.com" }

      post '/connexion', params: { identifier: "eater@example.com", otp_code: last_code }

      expect(response).to redirect_to(customers_account_path)
      expect(session[:customer_id]).to eq(customer.id)
    end

    it 'is case-insensitive on the email identifier' do
      customer = create(:customer, email: "eater@example.com", first_name: "Sam")
      post '/connexion', params: { identifier: "EATER@Example.com" }
      post '/connexion', params: { identifier: "EATER@Example.com", otp_code: last_code }

      expect(session[:customer_id]).to eq(customer.id)
    end

    it 'sends a code to an unknown email too (parity: anyone may request)' do
      expect {
        post '/connexion', params: { identifier: "newcomer@example.com" }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'invalid identifier' do
    it 'rejects gibberish that is neither a phone nor an email' do
      post '/connexion', params: { identifier: "pas valide" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Entre un numéro de GSM ou une adresse e-mail valide")
    end
  end

  describe 'wrong code' do
    it 'does not sign the customer in' do
      phone = "+32470555666"
      create(:customer, phone_e164: phone, first_name: "Léa")
      post '/connexion', params: { identifier: phone }

      post '/connexion', params: { identifier: phone, otp_code: "000000" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(session[:customer_id]).to be_nil
    end
  end

  describe 'unknown identifier — collect the name then create the account' do
    it 'asks for the name after a valid code (does not sign in yet) — email' do
      post '/connexion', params: { identifier: "newcomer@example.com" }
      post '/connexion', params: { identifier: "newcomer@example.com", otp_code: last_code }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("needs-name-marker")
      expect(response.body).to include("prénom")
      expect(session[:customer_id]).to be_nil
    end

    it 'creates the account and signs in on name submit — email' do
      post '/connexion', params: { identifier: "newcomer@example.com" }
      post '/connexion', params: { identifier: "newcomer@example.com", otp_code: last_code }

      expect {
        post '/connexion', params: { complete_signup: "1", first_name: "Robin", last_name: "Dubois" }
      }.to change(Customer, :count).by(1)

      customer = Customer.find_by(email: "newcomer@example.com")
      expect(customer.first_name).to eq("Robin")
      expect(customer.last_name).to eq("Dubois")
      expect(response).to redirect_to(customers_account_path)
      expect(session[:customer_id]).to eq(customer.id)
    end

    it 'creates the account and signs in on name submit — phone' do
      post '/connexion', params: { identifier: "+32470000111" }
      post '/connexion', params: { identifier: "+32470000111", otp_code: last_code }
      expect(session[:customer_id]).to be_nil

      expect {
        post '/connexion', params: { complete_signup: "1", first_name: "Alex" }
      }.to change(Customer, :count).by(1)

      customer = Customer.find_by(phone_e164: "+32470000111")
      expect(customer.first_name).to eq("Alex")
      expect(session[:customer_id]).to eq(customer.id)
    end

    it 'does not require re-verifying the code (verification already consumed)' do
      post '/connexion', params: { identifier: "newcomer@example.com" }
      post '/connexion', params: { identifier: "newcomer@example.com", otp_code: last_code }

      # The verification was destroyed on success; completing relies on session state.
      expect(PhoneVerification.for_email("newcomer@example.com")).to be_empty
      post '/connexion', params: { complete_signup: "1", first_name: "Robin" }
      expect(response).to redirect_to(customers_account_path)
    end

    it 're-prompts when the submitted name is blank' do
      post '/connexion', params: { identifier: "newcomer2@example.com" }
      post '/connexion', params: { identifier: "newcomer2@example.com", otp_code: last_code }

      expect {
        post '/connexion', params: { complete_signup: "1", first_name: "" }
      }.not_to change(Customer, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(session[:customer_id]).to be_nil
    end

    it 'rejects a signup completion with no verified identifier in session' do
      post '/connexion', params: { complete_signup: "1", first_name: "Mallory" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(session[:customer_id]).to be_nil
    end
  end
end
