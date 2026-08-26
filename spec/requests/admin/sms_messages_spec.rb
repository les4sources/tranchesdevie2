require "rails_helper"

RSpec.describe "Admin::SmsMessages", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  describe "GET /admin/customers/:customer_id/sms_messages/:id" do
    it "affiche le détail d'un SMS sortant" do
      customer = create(:customer, phone_e164: "+32470000001")
      sms = create(:sms_message,
                   customer: customer,
                   kind: :confirmation,
                   direction: :outbound,
                   to_e164: customer.phone_e164,
                   body: "Votre commande est confirmée.")

      get admin_customer_sms_message_path(customer, sms)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Détails du message SMS")
      expect(response.body).to include("Confirmation")
      expect(response.body).to include("Sortant")
      expect(response.body).to include("Votre commande est confirmée.")
    end

    it "affiche un SMS entrant comme entrant" do
      customer = create(:customer)
      sms = create(:sms_message, customer: customer, kind: :other, direction: :inbound)

      get admin_customer_sms_message_path(customer, sms)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Entrant")
    end
  end
end
