require 'rails_helper'

RSpec.describe 'Customers::Account', type: :request do
  let(:customer) { create(:customer, email: "eater@example.com", email_opt_out: false) }

  def authenticate_customer
    allow(OtpService).to receive(:send_otp).and_return({ success: true })
    allow(OtpService).to receive(:verify_otp).and_return({ success: true })

    post '/connexion', params: { phone_e164: customer.phone_e164 }
    post '/connexion', params: { phone_e164: customer.phone_e164, otp_code: '123456' }
  end

  before { authenticate_customer }

  describe 'GET /customers/mon-compte/edit' do
    it 'renders the profile form with the email preference toggle' do
      get customers_edit_account_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email_opt_out")
      expect(response.body).to include("Désactiver les e-mails")
    end
  end

  describe 'PATCH /customers/mon-compte' do
    it 'lets the customer disable non-OTP emails' do
      patch customers_account_path, params: { customer: { email_opt_out: "1" } }
      expect(customer.reload.email_opt_out).to be true
    end
  end
end
