require "rails_helper"

RSpec.describe "Admin::Customers", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  # #36 : réglage admin « paiement cash autorisé » sur le client.
  describe "PATCH /admin/customers/:id" do
    it "autorise le paiement cash pour le client" do
      customer = create(:customer, cash_payment_allowed: false)

      patch admin_customer_path(customer), params: {
        customer: { first_name: customer.first_name, cash_payment_allowed: "1" }
      }

      expect(customer.reload.cash_payment_allowed).to be(true)
    end

    it "retire l'autorisation de paiement cash" do
      customer = create(:customer, cash_payment_allowed: true)

      patch admin_customer_path(customer), params: {
        customer: { first_name: customer.first_name, cash_payment_allowed: "0" }
      }

      expect(customer.reload.cash_payment_allowed).to be(false)
    end
  end
end
