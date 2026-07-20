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

  it "affiche la section parties publiques avec le barème public" do
    bake_day = create(:bake_day, baked_on: date)
    customer = create(:customer, first_name: "Bob", last_name: "Martin")
    product = create(:product, :pizza_party_public, name: "Pizza party publique")
    adulte = create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300)
    enfant = create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200)
    create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: date - 30)
    create(:variant_cost_price, product_variant: enfant, amount_cents: 26, active_from: date - 30)
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: date - 60)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1_600)
    create(:order_item, order: order, product_variant: adulte, qty: 1, unit_price_cents: 1_000)
    create(:order_item, order: order, product_variant: enfant, qty: 1, unit_price_cents: 600)

    get pizza_parties_admin_reports_path, params: { start_date: "2026-07-01", end_date: "2026-07-31" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Parties publiques")
    expect(response.body).to include("Bob Martin")
    expect(response.body).to include("7,34 €")  # boulangers 472 + 262
    expect(response.body).to include("8,14 €")  # 4 Sources 502 + 312
  end

  it "affiche la section historique BilletWeb avec le barème rétroactif" do
    product = create(:product, :pizza_party_public, name: "Pizza party publique")
    create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300)
    create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200)
    create(:party_event, :public_party,
           title: "Pizza Party de juillet", held_on: Date.new(2026, 7, 18),
           historical_source: "billetweb", historical_adults: 35, historical_children: 16, historical_fees_cents: 2_713)

    get pizza_parties_admin_reports_path, params: { start_date: "2026-07-01", end_date: "2026-07-31" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Parties publiques historiques (BilletWeb)")
    expect(response.body).to include("Pizza Party de juillet")
    expect(response.body).to include("216,30 €")  # boulangers dus (barème rétro)
    expect(response.body).to include("418,87 €")  # 4S net encaissé (446 − 27,13)
  end
end
