require "rails_helper"

# Page « Feuille compta » d'un jour de cuisson (#feuille-compta).
RSpec.describe "Admin bake day sheet", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:date) { Date.new(2026, 5, 12) }
  let(:bake_day) { create(:bake_day, baked_on: date) }

  it "affiche la feuille compta avec les formats vendus et le total boulangers" do
    customer = create(:customer)
    product = create(:product, category: :breads, internal_category: :boulangerie, name: "Pain froment")
    variant = create(:product_variant, product: product, name: "1 kg", price_cents: 550)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1_100)
    create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 550)

    get sheet_admin_bake_day_path(bake_day)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Feuille compta")
    expect(response.body).to include("Pain froment – 1 kg")
    expect(response.body).to include("Total boulangers")
    expect(response.body).to include("Répartition boulangers / 4 Sources")
  end
end
