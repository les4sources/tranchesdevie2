require "rails_helper"

# Admin : reporting des revenus des boulangers (#54). Vérifie que la page rend,
# affiche les colonnes attendues, filtre par période / par jour de production,
# et affiche l'avertissement quand la somme des parts des présents dépasse 100 %.
RSpec.describe "Admin::Reports baker_revenue", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def login_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  def bread_variant(price_cents:, cost_cents:)
    product = create(:product, category: :breads, internal_category: :boulangerie)
    variant = create(:product_variant, product: product, price_cents: price_cents)
    create(:variant_cost_price, product_variant: variant, amount_cents: cost_cents, active_from: Date.new(2026, 1, 1))
    variant
  end

  def completed_order(bake_day:, variant:, qty:)
    order = create(:order, :paid, bake_day: bake_day, total_cents: qty * variant.price_cents)
    create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: variant.price_cents)
    order
  end

  it "exige une authentification" do
    get baker_revenue_admin_reports_path
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before do
      login_admin
      create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    end

    it "rend la page avec toutes les colonnes du détail" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      variant = bread_variant(price_cents: 1_000, cost_cents: 400)
      completed_order(bake_day: bake_day, variant: variant, qty: 10)
      claire = create(:artisan, name: "Claire")
      create(:bake_day_artisan, bake_day: bake_day, artisan: claire)
      create(:artisan_revenue_share, artisan: claire, percent: 100, active_from: Date.new(2026, 1, 1))

      get baker_revenue_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      # Colonnes attendues
      expect(response.body).to include("Chiffre d'affaires")
      expect(response.body).to include("Coûtant")
      expect(response.body).to include("Sacs")
      expect(response.body).to include("Transport")
      expect(response.body).to include("Marge brute")
      expect(response.body).to include("Part 4S").or include("Part Les 4 Sources")
      expect(response.body).to include("Pool")
      expect(response.body).to include("Revenu par boulanger")
      # Le boulanger et son revenu (pool = 3122 → 31,22 €) apparaissent.
      expect(response.body).to include("Claire")
      expect(response.body).to include("31,22")
    end

    it "ventile par jour de production (deux lignes pour deux jours)" do
      variant = bread_variant(price_cents: 1_000, cost_cents: 400)
      day1 = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      day2 = create(:bake_day, baked_on: Date.new(2026, 5, 15))
      [ day1, day2 ].each { |bd| completed_order(bake_day: bd, variant: variant, qty: 10) }

      get baker_revenue_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.l(Date.new(2026, 5, 12)))
      expect(response.body).to include(I18n.l(Date.new(2026, 5, 15)))
    end

    it "respecte le filtre de période (un jour hors période n'apparaît pas)" do
      variant = bread_variant(price_cents: 1_000, cost_cents: 400)
      in_range = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      out_of_range = create(:bake_day, baked_on: Date.new(2026, 6, 12))
      completed_order(bake_day: in_range, variant: variant, qty: 10)
      completed_order(bake_day: out_of_range, variant: variant, qty: 10)

      get baker_revenue_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response.body).to include(I18n.l(Date.new(2026, 5, 12)))
      expect(response.body).not_to include(I18n.l(Date.new(2026, 6, 12)))
    end

    it "affiche l'avertissement quand la somme des parts des présents dépasse 100 %" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      variant = bread_variant(price_cents: 1_000, cost_cents: 400)
      completed_order(bake_day: bake_day, variant: variant, qty: 10)

      a = create(:artisan, name: "Alpha")
      b = create(:artisan, name: "Beta")
      [ a, b ].each { |artisan| create(:bake_day_artisan, bake_day: bake_day, artisan: artisan) }
      create(:artisan_revenue_share, artisan: a, percent: 70, active_from: Date.new(2026, 1, 1))
      create(:artisan_revenue_share, artisan: b, percent: 60, active_from: Date.new(2026, 1, 1))

      get baker_revenue_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Avertissements")
      expect(response.body).to include("&gt; 100 %").or include("> 100 %")
    end
  end
end
