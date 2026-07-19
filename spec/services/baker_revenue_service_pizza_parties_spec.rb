require "rails_helper"

# Intégration du barème PIZZA PARTY PRIVÉE dans la paie (#pizza-parties).
# La party est calculée hors 70/30 (barème spécial) puis combinée à la marge
# des pains. Sans party, le comportement reste identique (couvert par
# baker_revenue_service_spec.rb).
RSpec.describe "BakerRevenueService — pizza parties privées", type: :model do
  let(:date) { Date.new(2026, 5, 12) }
  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }
  let(:bake_day) { create(:bake_day, baked_on: date) }
  let(:artisan) { create(:artisan, name: "Romane") }

  subject(:report) { BakerRevenueService.new(start_date: start_date, end_date: end_date).call }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:revenue_parameter, :transport, value: 0, active_from: Date.new(2026, 1, 1))
    create(:bread_bag_price, amount_cents: 0, active_from: Date.new(2026, 1, 1))
    create(:artisan_revenue_share, artisan: artisan, percent: 100, active_from: Date.new(2026, 1, 1))
    create(:bake_day_artisan, bake_day: bake_day, artisan: artisan)
  end

  def party_variants
    party_product = create(:product, :pizza_party)
    party_variant = create(:product_variant, product: party_product, price_cents: 500)
    create(:variant_cost_price, product_variant: party_variant, amount_cents: 26, active_from: date - 30)
    forfait_product = create(:product, :pizza_party_forfait)
    forfait_variant = create(:product_variant, product: forfait_product, price_cents: 4000)
    [ party_variant, forfait_variant ]
  end

  def add_party_order(persons:)
    pv, fv = party_variants
    order = create(:order, :paid, bake_day: bake_day, total_cents: persons * 500 + 4000)
    create(:order_item, order: order, product_variant: pv, qty: persons, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: fv, qty: 1, unit_price_cents: 4000)
    order
  end

  def add_bread_order(qty:, price_cents:, cost_cents:)
    product = create(:product, category: :breads, internal_category: :boulangerie)
    variant = create(:product_variant, product: product, price_cents: price_cents)
    create(:variant_cost_price, product_variant: variant, amount_cents: cost_cents, active_from: Date.new(2026, 1, 1))
    order = create(:order, :paid, bake_day: bake_day, total_cents: qty * price_cents)
    create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: price_cents)
    order
  end

  def add_public_party_order(adults:, children:)
    product = create(:product, :pizza_party_public)
    adulte = create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300)
    enfant = create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200)
    create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: date - 30)
    create(:variant_cost_price, product_variant: enfant, amount_cents: 26, active_from: date - 30)
    order = create(:order, :paid, bake_day: bake_day, total_cents: adults * 1_000 + children * 600)
    create(:order_item, order: order, product_variant: adulte, qty: adults, unit_price_cents: 1_000) if adults.positive?
    create(:order_item, order: order, product_variant: enfant, qty: children, unit_price_cents: 600) if children.positive?
    order
  end

  context "journée avec UNIQUEMENT une pizza party (10 pers, coûtant 0,26 €)" do
    before { add_party_order(persons: 10) }

    it "applique le barème spécial, isolé dans les champs party" do
      day = report.days.first
      expect(day.party_persons).to eq(10)
      expect(day.party_revenue_cents).to eq(9_000)
      expect(day.party_four_sources_cents).to eq(2_600)
      expect(day.party_bakers_cents).to eq(6_140)
    end

    it "n'applique PAS le 70/30 à la party : four_sources/pool = split party" do
      day = report.days.first
      expect(day.four_sources_cents).to eq(2_600)
      expect(day.baker_pool_cents).to eq(6_140)
    end

    it "verse la part boulangers de la party à l'artisan présent (100 %)" do
      settlement = report.artisan_settlements.find { |s| s.artisan == artisan }
      expect(settlement.settled_cents).to eq(6_140)
    end

    it "remonte les cumuls party dans le rapport" do
      expect(report.total_party_persons).to eq(10)
      expect(report.total_party_bakers_cents).to eq(6_140)
      expect(report.total_party_four_sources_cents).to eq(2_600)
    end
  end

  context "journée MIXTE pain + party" do
    before do
      add_bread_order(qty: 10, price_cents: 1_000, cost_cents: 400)
      add_party_order(persons: 10)
    end

    it "combine le 70/30 du pain et le split spécial de la party" do
      day = report.days.first
      # Marge pain (hors party) = (19000 − 9000) − 4000 − 0 − 0 − 0 = 6000
      #   4S pain = 30 % × 6000 = 1800 ; pool pain = 4200
      # + party : 4S 2600, boulangers 6140
      expect(day.revenue_cents).to eq(19_000)
      expect(day.four_sources_cents).to eq(1_800 + 2_600)   # 4400
      expect(day.baker_pool_cents).to eq(4_200 + 6_140)     # 10340
    end
  end

  context "sans aucune party" do
    before { add_bread_order(qty: 10, price_cents: 1_000, cost_cents: 400) }

    it "laisse le calcul strictement inchangé (party = 0)" do
      day = report.days.first
      expect(day.party_persons).to eq(0)
      expect(day.party_bakers_cents).to eq(0)
      expect(day.public_party_persons).to eq(0)
      # marge pain = 10000 − 4000 = 6000 ; 4S 1800 ; pool 4200
      expect(day.four_sources_cents).to eq(1_800)
      expect(day.baker_pool_cents).to eq(4_200)
    end
  end

  context "journée avec une party PUBLIQUE (1 adulte + 1 enfant)" do
    before { add_public_party_order(adults: 1, children: 1) }

    it "applique le barème public, isolé dans les champs public_party" do
      day = report.days.first
      expect(day.public_party_persons).to eq(2)
      # adulte : 4S 502 / boulangers 472 ; enfant : 4S 312 / boulangers 262
      expect(day.public_party_four_sources_cents).to eq(502 + 312)
      expect(day.public_party_bakers_cents).to eq(472 + 262)
    end

    it "verse la part boulangers publique à l'artisan présent (100 %)" do
      settlement = report.artisan_settlements.find { |s| s.artisan == artisan }
      expect(settlement.settled_cents).to eq(472 + 262)
    end
  end
end
