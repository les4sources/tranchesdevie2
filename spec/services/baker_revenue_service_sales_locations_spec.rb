require "rails_helper"

# Déduction du coût des lieux de vente (#150) dans le calcul des revenus
# boulangers : le coût des lieux liés à une fournée (résolu à sa date de cuisson)
# est retranché de la marge brute AVANT le partage 70/30.
RSpec.describe BakerRevenueService do
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

  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
  let(:variant) { bread_variant(price_cents: 1_000, cost_cents: 400) }

  subject(:report) { described_class.new(start_date: start_date, end_date: end_date).call }

  before do
    create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 1, 1))
    create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    completed_order(bake_day: bake_day, variant: variant, qty: 10)
  end

  # Sans lieu de vente : marge brute de référence = 10000 − 4000 − 40 − 1500 = 4460.
  context "sans lieu de vente lié" do
    it "ne déduit rien : marge brute et split inchangés" do
      day = report.days.first

      expect(day.sales_locations_cents).to eq(0)
      expect(day.gross_margin_cents).to eq(4_460)
      expect(day.four_sources_cents).to eq(1_338)
      expect(day.baker_pool_cents).to eq(3_122)
      expect(report.total_sales_locations_cents).to eq(0)
    end
  end

  context "avec un lieu de vente lié" do
    before do
      location = create(:sales_location, name: "Marché d'Anhée")
      create(:sales_location_cost, sales_location: location, amount_cents: 2_000,
             valid_from: Date.new(2026, 1, 1), valid_until: nil)
      bake_day.sales_locations << location
    end

    it "déduit le coût du lieu de la marge brute avant le split" do
      day = report.days.first

      expect(day.sales_locations_cents).to eq(2_000)
      # marge brute = 4460 − 2000 = 2460
      expect(day.gross_margin_cents).to eq(2_460)
      # 4S = 30 % × 2460 = 738 ; pool = 2460 − 738 = 1722
      expect(day.four_sources_cents).to eq(738)
      expect(day.baker_pool_cents).to eq(1_722)
      expect(report.total_sales_locations_cents).to eq(2_000)
    end
  end

  context "avec deux lieux de vente liés" do
    before do
      [ [ "Anhée", 2_000 ], [ "Dinant", 1_500 ] ].each do |name, cost|
        location = create(:sales_location, name: name)
        create(:sales_location_cost, sales_location: location, amount_cents: cost,
               valid_from: Date.new(2026, 1, 1), valid_until: nil)
        bake_day.sales_locations << location
      end
    end

    it "cumule les coûts des deux lieux" do
      day = report.days.first

      expect(day.sales_locations_cents).to eq(3_500)
      # marge brute = 4460 − 3500 = 960
      expect(day.gross_margin_cents).to eq(960)
      # 4S = 30 % × 960 = 288 ; pool = 672
      expect(day.four_sources_cents).to eq(288)
      expect(day.baker_pool_cents).to eq(672)
    end
  end

  context "quand le coût du lieu évolue dans le temps" do
    before do
      location = create(:sales_location, name: "Marché d'Anhée")
      # Période antérieure à la fournée (mai) : ne doit PAS s'appliquer.
      create(:sales_location_cost, sales_location: location, amount_cents: 9_999,
             valid_from: Date.new(2025, 1, 1), valid_until: Date.new(2026, 4, 30))
      # Période couvrant la fournée du 12/05.
      create(:sales_location_cost, sales_location: location, amount_cents: 2_000,
             valid_from: Date.new(2026, 5, 1), valid_until: nil)
      bake_day.sales_locations << location
    end

    it "applique le coût de la période qui couvre la date de cuisson" do
      expect(report.days.first.sales_locations_cents).to eq(2_000)
    end
  end
end
