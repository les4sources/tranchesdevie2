require "rails_helper"

# Admin : vue de facturation mensuelle des clients professionnels (ISC-45).
RSpec.describe "Admin::Billing", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def login_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  it "exige une authentification" do
    get admin_billing_path
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before { login_admin }

    let(:month) { Date.new(2026, 5, 1) }
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let!(:pro) { create(:customer, billable: true, first_name: "Épicerie", last_name: "Durand") }
    let!(:order) do
      create(:order, :unpaid, customer: pro, bake_day: bake_day, total_cents: 1500).tap do |o|
        create(:order_item, order: o, qty: 3)
      end
    end

    it "affiche le récapitulatif du mois pour les clients facturables" do
      get admin_billing_path(month: "2026-05")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Épicerie Durand")
      expect(response.body).to include("Impayé")
    end

    it "exporte le récapitulatif en CSV" do
      get admin_billing_path(month: "2026-05", format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Client")
      expect(response.body).to include("Épicerie Durand")
    end

    it "tolère un mois invalide en retombant sur le mois courant" do
      get admin_billing_path(month: "pas-une-date")
      expect(response).to have_http_status(:ok)
    end
  end
end
