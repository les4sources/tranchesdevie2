require 'rails_helper'

RSpec.describe "Admin::EmailMessages", type: :request do
  let(:customer) { create(:customer, email: "eater@example.com") }
  let!(:email_message) do
    create(:email_message, customer: customer, to_email: customer.email,
                           subject: "Confirmation de ta commande TV-1", body_html: "<p>Merci !</p>")
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ADMIN_PASSWORD').and_return('secret')
    post admin_login_path, params: { password: 'secret' }
  end

  describe "GET /admin/customers/:id (show)" do
    it "renders the sent-emails section" do
      get admin_customer_path(customer)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("E-mails envoyés")
      expect(response.body).to include(email_message.subject)
    end
  end

  describe "GET /admin/customers/:customer_id/email_messages/:id" do
    it "returns the email details as JSON" do
      get admin_customer_email_message_path(customer, email_message, format: :json)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["subject"]).to eq(email_message.subject)
      expect(body["body_html"]).to include("Merci !")
    end
  end

  describe "POST /admin/customers/:customer_id/email_messages/:id/resend" do
    it "re-delivers the email and logs a new EmailMessage" do
      expect {
        post resend_admin_customer_email_message_path(customer, email_message)
      }.to change(EmailMessage, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
      expect(ActionMailer::Base.deliveries.last.to).to eq([ customer.email ])
    end
  end
end
