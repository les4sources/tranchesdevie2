require 'rails_helper'

RSpec.describe "Email preferences", type: :request do
  let(:customer) { create(:customer, email: "eater@example.com", email_opt_out: false) }
  let(:token) { customer.signed_id(purpose: :email_unsubscribe) }

  describe "GET /e-mails/preferences/:token" do
    it "shows the preferences page for a valid token" do
      get email_preferences_path(token: token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(customer.email)
    end

    it "redirects to root for an invalid token" do
      get email_preferences_path(token: "not-a-real-token")
      expect(response).to redirect_to(root_path)
    end
  end

  describe "PATCH /e-mails/preferences/:token" do
    it "opts the customer out of emails" do
      patch email_preferences_path(token: token), params: { email_opt_out: "true" }
      expect(customer.reload.email_opt_out).to be true
      expect(response).to redirect_to(email_preferences_path(token: token))
    end

    it "opts the customer back in" do
      customer.update!(email_opt_out: true)
      patch email_preferences_path(token: token), params: { email_opt_out: "false" }
      expect(customer.reload.email_opt_out).to be false
    end

    it "ignores an invalid token" do
      patch email_preferences_path(token: "nope"), params: { email_opt_out: "true" }
      expect(response).to redirect_to(root_path)
    end
  end
end
