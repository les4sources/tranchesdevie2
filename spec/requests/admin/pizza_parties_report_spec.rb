require "rails_helper"

# Vue reporting dédiée aux pizza parties privées (#pizza-parties) : affiche le
# barème spécial (PizzaPartyRevenueService) pour évaluer l'intérêt de l'offre.
RSpec.describe "Admin::Reports pizza parties", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:date) { Date.new(2026, 7, 10) }

  def party_order(persons:)
    bake_day = create(:bake_day, baked_on: date)
    customer = create(:customer, first_name: "Alba", last_name: "Zorro")
    party_product = create(:product, :pizza_party, name: "Pizza party privée – Nombre de personnes")
    party_variant = create(:product_variant, product: party_product, name: "une boule", price_cents: 500)
    forfait_product = create(:product, :pizza_party_forfait, name: "Forfait Pizza party")
    forfait_variant = create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4000)
    create(:variant_cost_price, product_variant: party_variant, amount_cents: 26, active_from: date - 30)

    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: persons * 500 + 4000)
    create(:order_item, order: order, product_variant: party_variant, qty: persons, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait_variant, qty: 1, unit_price_cents: 4000)
    order
  end

  it "affiche le barème party (4S 26 €, boulangers 61,40 € pour 10 pers)" do
    party_order(persons: 10)

    get pizza_parties_admin_reports_path, params: { start_date: "2026-07-01", end_date: "2026-07-31" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pizza parties privées")
    expect(response.body).to include("Alba Zorro")
    expect(response.body).to include("90,00 €")  # CA
    expect(response.body).to include("2,60 €")   # coûtant
    expect(response.body).to include("61,40 €")  # part boulangers
    expect(response.body).to include("26,00 €")  # part 4 Sources
  end

  it "affiche un état vide quand aucune party sur la période" do
    get pizza_parties_admin_reports_path, params: { start_date: "2026-07-01", end_date: "2026-07-31" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucune pizza party privée sur cette période.")
  end
end
