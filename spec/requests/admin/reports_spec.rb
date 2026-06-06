require "rails_helper"

# Admin : reporting des ventes, dont la ventilation par catégorie interne (ISC-46).
RSpec.describe "Admin::Reports", type: :request do
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
    get admin_reports_path
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before { login_admin }

    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:bakery_variant) do
      create(:product_variant, product: create(:product, internal_category: :boulangerie))
    end
    let(:grocery_variant) do
      create(:product_variant, product: create(:product, :epicerie))
    end

    it "affiche la ventilation des ventes par catégorie interne" do
      order = create(:order, :paid, bake_day: bake_day)
      create(:order_item, order: order, product_variant: bakery_variant, qty: 2, unit_price_cents: 500)
      create(:order_item, order: order, product_variant: grocery_variant, qty: 1, unit_price_cents: 300)

      get admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ventes par catégorie interne")
      expect(response.body).to include("Boulangerie")
      expect(response.body).to include("Épicerie")
    end

    it "fonctionne sans aucune vente sur la période" do
      get admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ventes par catégorie interne")
    end
  end
end
