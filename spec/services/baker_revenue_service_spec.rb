require "rails_helper"

# Moteur de calcul des revenus boulangers (#54).
#
# Invariants couverts :
#   - marge brute = CA − coûtant (#90) − sacs (#52) − transport (#54)
#   - split 30 % aux 4 Sources / 70 % pool boulangers (sur la marge brute)
#   - répartition du pool par artisan PRÉSENT (#26) au % LITTÉRAL (sans normalisation)
#   - historisation : un nouveau palier de paramètre n'affecte pas le passé
#   - avertissement si la somme des parts des présents dépasse 100 %
#   - consolidation par jour, par période, et cumul par artisan (additionnable)
RSpec.describe BakerRevenueService do
  # --- Helpers de fixture -----------------------------------------------------

  # Crée une variante de PAIN produit maison avec un prix coûtant historisé (#90).
  def bread_variant(price_cents:, cost_cents:, cost_from: Date.new(2026, 1, 1))
    product = create(:product, category: :breads, internal_category: :boulangerie)
    variant = create(:product_variant, product: product, price_cents: price_cents)
    create(:variant_cost_price, product_variant: variant, amount_cents: cost_cents, active_from: cost_from)
    variant
  end

  # Crée une commande finalisée d'un seul article sur un jour donné, avec un
  # total cohérent avec la ligne.
  def completed_order(bake_day:, variant:, qty:, unit_price_cents: variant.price_cents)
    order = create(:order, :paid, bake_day: bake_day, total_cents: qty * unit_price_cents)
    create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: unit_price_cents)
    order
  end

  def assign_artisan(bake_day:, artisan:)
    create(:bake_day_artisan, bake_day: bake_day, artisan: artisan)
  end

  def configure_share(artisan:, percent:, from: Date.new(2026, 1, 1))
    create(:artisan_revenue_share, artisan: artisan, percent: percent, active_from: from)
  end

  # Prix de sac par défaut (#52) : 0,04 €.
  before do
    create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 1, 1))
  end

  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }

  subject(:report) { described_class.new(start_date: start_date, end_date: end_date).call }

  # --- Marge brute ------------------------------------------------------------

  describe "marge brute = CA − coûtant − sacs − transport" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:variant) { bread_variant(price_cents: 1_000, cost_cents: 400) }

    before do
      # Transport 15 €/jour, taux 4S 30 %.
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
      completed_order(bake_day: bake_day, variant: variant, qty: 10)
    end

    it "déduit coûtant, sacs et transport du CA" do
      day = report.days.first

      # CA = 10 × 1000 = 10000
      expect(day.revenue_cents).to eq(10_000)
      # coûtant = 10 × 400 = 4000
      expect(day.cost_price_cents).to eq(4_000)
      # sacs = 10 pains × 4 = 40
      expect(day.bread_bags_cents).to eq(40)
      # transport = 1500
      expect(day.transport_cents).to eq(1_500)
      # marge brute = 10000 − 4000 − 40 − 1500 = 4460
      expect(day.gross_margin_cents).to eq(4_460)
    end

    it "applique le split 30 % / 70 % sur la marge brute" do
      day = report.days.first

      # 4S = 30 % × 4460 = 1338
      expect(day.four_sources_cents).to eq(1_338)
      # pool = 4460 − 1338 = 3122
      expect(day.baker_pool_cents).to eq(3_122)
    end

    it "consolide les totaux de période" do
      expect(report.total_revenue_cents).to eq(10_000)
      expect(report.total_cost_price_cents).to eq(4_000)
      expect(report.total_bread_bags_cents).to eq(40)
      expect(report.total_transport_cents).to eq(1_500)
      expect(report.gross_margin_cents).to eq(4_460)
      expect(report.four_sources_cents).to eq(1_338)
      expect(report.baker_pool_cents).to eq(3_122)
    end

    it "exclut les reventes épicerie/traiteur du coûtant (sacs déjà exclus #52)" do
      grocery = create(:product_variant, product: create(:product, :epicerie), price_cents: 500)
      create(:variant_cost_price, product_variant: grocery, amount_cents: 200, active_from: Date.new(2026, 1, 1))
      completed_order(bake_day: bake_day, variant: grocery, qty: 4)

      day = report.days.first
      # CA inclut la revente (10×1000 + 4×500 = 12000), mais le coûtant reste sur
      # le seul pain maison (4000) et les sacs aussi (40, l'épicerie n'en compte pas).
      expect(day.revenue_cents).to eq(12_000)
      expect(day.cost_price_cents).to eq(4_000)
      expect(day.bread_bags_cents).to eq(40)
    end

    it "ignore les commandes annulées dans le CA" do
      create(:order, :cancelled, bake_day: bake_day, total_cents: 9_999)
      expect(report.days.first.revenue_cents).to eq(10_000)
    end
  end

  # --- Répartition par artisan ------------------------------------------------

  describe "répartition du pool par artisan présent (% littéral)" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:variant) { bread_variant(price_cents: 1_000, cost_cents: 400) }

    before do
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
      completed_order(bake_day: bake_day, variant: variant, qty: 10)
      # pool attendu = 3122 (voir bloc précédent)
    end

    it "attribue 100 % du pool à un seul artisan présent à 100 %" do
      claire = create(:artisan, name: "Claire")
      assign_artisan(bake_day: bake_day, artisan: claire)
      configure_share(artisan: claire, percent: 100)

      day = report.days.first
      expect(day.artisan_shares.size).to eq(1)
      expect(day.artisan_shares.first.amount_cents).to eq(3_122)
      expect(day.percent_overflow).to be(false)
    end

    it "répartit 50/50 entre deux entités présentes" do
      duo = create(:artisan, name: "Romane & Thomas")
      michael = create(:artisan, name: "Michaël")
      assign_artisan(bake_day: bake_day, artisan: duo)
      assign_artisan(bake_day: bake_day, artisan: michael)
      configure_share(artisan: duo, percent: 50)
      configure_share(artisan: michael, percent: 50)

      amounts = report.days.first.artisan_shares.to_h { |s| [ s.artisan.name, s.amount_cents ] }
      # 50 % × 3122 = 1561 chacun
      expect(amounts["Romane & Thomas"]).to eq(1_561)
      expect(amounts["Michaël"]).to eq(1_561)
    end

    it "applique le % LITTÉRAL sans normalisation (somme < 100 %)" do
      solo = create(:artisan, name: "Solo")
      assign_artisan(bake_day: bake_day, artisan: solo)
      configure_share(artisan: solo, percent: 50)

      # 50 % littéral × 3122 = 1561 (et NON 100 % via normalisation).
      expect(report.days.first.artisan_shares.first.amount_cents).to eq(1_561)
    end

    it "attribue 0 à un artisan présent sans part configurée" do
      sans_part = create(:artisan, name: "Sans part")
      assign_artisan(bake_day: bake_day, artisan: sans_part)

      share = report.days.first.artisan_shares.first
      expect(share.percent).to be_nil
      expect(share.amount_cents).to eq(0)
    end
  end

  # --- Avertissement > 100 % --------------------------------------------------

  describe "avertissement si somme des parts des présents > 100 %" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:variant) { bread_variant(price_cents: 1_000, cost_cents: 400) }

    before do
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
      completed_order(bake_day: bake_day, variant: variant, qty: 10)
    end

    it "lève un avertissement sans corriger automatiquement" do
      a = create(:artisan, name: "A")
      b = create(:artisan, name: "B")
      assign_artisan(bake_day: bake_day, artisan: a)
      assign_artisan(bake_day: bake_day, artisan: b)
      configure_share(artisan: a, percent: 70)
      configure_share(artisan: b, percent: 60) # somme = 130 %

      day = report.days.first
      expect(day.percent_overflow).to be(true)
      expect(report.warnings).not_to be_empty
      expect(report.warnings.first).to include("> 100 %")
      # Pas de correction : 70 % × 3122 = 2185, 60 % × 3122 = 1873 (somme > pool).
      amounts = day.artisan_shares.map(&:amount_cents)
      expect(amounts.sum).to be > day.baker_pool_cents
    end

    it "ne lève aucun avertissement quand la somme est ≤ 100 %" do
      a = create(:artisan, name: "A")
      assign_artisan(bake_day: bake_day, artisan: a)
      configure_share(artisan: a, percent: 100)

      expect(report.warnings).to be_empty
    end
  end

  # --- Historisation ----------------------------------------------------------

  describe "historisation : un nouveau palier n'affecte pas une période antérieure" do
    let(:variant) { bread_variant(price_cents: 1_000, cost_cents: 400) }

    it "utilise le transport en vigueur à la date du jour" do
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :transport, value: 3_000, active_from: Date.new(2026, 6, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))

      old_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      completed_order(bake_day: old_day, variant: variant, qty: 10)

      # Mai → transport encore à 1500 (le palier de juin ne rétroagit pas).
      expect(report.days.first.transport_cents).to eq(1_500)
    end

    it "utilise le taux 4S en vigueur à la date du jour" do
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 4_000, active_from: Date.new(2026, 6, 1))

      day_in_may = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      completed_order(bake_day: day_in_may, variant: variant, qty: 10)

      # marge = 4460 ; 4S = 30 % (palier de janvier), pas 40 %.
      expect(report.days.first.four_sources_cents).to eq(1_338)
    end

    it "utilise la part artisan en vigueur à la date du jour" do
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))

      day_in_may = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      completed_order(bake_day: day_in_may, variant: variant, qty: 10)

      artisan = create(:artisan, name: "Évolutif")
      assign_artisan(bake_day: day_in_may, artisan: artisan)
      configure_share(artisan: artisan, percent: 50, from: Date.new(2026, 1, 1))
      configure_share(artisan: artisan, percent: 100, from: Date.new(2026, 6, 1))

      # Mai → 50 % (le palier de juin ne rétroagit pas) : 50 % × 3122 = 1561.
      expect(report.days.first.artisan_shares.first.amount_cents).to eq(1_561)
    end
  end

  # --- Consolidation par jour et par artisan ----------------------------------

  describe "consolidation par jour et cumul par artisan" do
    let(:variant) { bread_variant(price_cents: 1_000, cost_cents: 400) }

    before do
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    end

    it "produit une ligne par jour de production et cumule par artisan" do
      claire = create(:artisan, name: "Claire")
      configure_share(artisan: claire, percent: 100)

      day1 = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      day2 = create(:bake_day, baked_on: Date.new(2026, 5, 15))
      [ day1, day2 ].each do |bake_day|
        completed_order(bake_day: bake_day, variant: variant, qty: 10)
        assign_artisan(bake_day: bake_day, artisan: claire)
      end

      expect(report.days.map(&:date)).to eq([ Date.new(2026, 5, 12), Date.new(2026, 5, 15) ])

      # Cumul Claire = 2 × 3122 = 6244, sur 2 jours.
      total = report.artisan_totals.find { |t| t.artisan == claire }
      expect(total.amount_cents).to eq(6_244)
      expect(total.days_count).to eq(2)
    end

    it "ne cumule par artisan que sur la période demandée (additionnable par mois)" do
      claire = create(:artisan, name: "Claire")
      configure_share(artisan: claire, percent: 100)

      may_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      june_day = create(:bake_day, baked_on: Date.new(2026, 6, 12))
      [ may_day, june_day ].each do |bake_day|
        completed_order(bake_day: bake_day, variant: variant, qty: 10)
        assign_artisan(bake_day: bake_day, artisan: claire)
      end

      may_report = described_class.new(start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 31)).call
      june_report = described_class.new(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30)).call

      may_total = may_report.artisan_totals.find { |t| t.artisan == claire }.amount_cents
      june_total = june_report.artisan_totals.find { |t| t.artisan == claire }.amount_cents

      # Les totaux mensuels s'additionnent pour reconstituer la période complète.
      expect(may_total).to eq(3_122)
      expect(june_total).to eq(3_122)
      expect(may_total + june_total).to eq(6_244)
    end
  end
end
