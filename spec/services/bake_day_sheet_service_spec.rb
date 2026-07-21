require "rails_helper"

# Feuille compta par jour de cuisson (#feuille-compta) : ventile le CA net par
# format et expose le split boulangers/4S AUTHORITATIVE (BakerRevenueService).
RSpec.describe BakeDaySheetService do
  let(:date) { Date.new(2026, 5, 12) }
  let(:bake_day) { create(:bake_day, baked_on: date) }
  let(:customer) { create(:customer) }
  let(:product) { create(:product, category: :breads, internal_category: :boulangerie, name: "Pain froment") }
  let(:v1kg) { create(:product_variant, product: product, name: "1 kg", price_cents: 550) }
  let(:v800) { create(:product_variant, product: product, name: "800 g", price_cents: 450) }

  before do
    create(:variant_cost_price, product_variant: v1kg, amount_cents: 109, active_from: date - 30)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 550 * 2 + 450)
    create(:order_item, order: order, product_variant: v1kg, qty: 2, unit_price_cents: 550)
    create(:order_item, order: order, product_variant: v800, qty: 1, unit_price_cents: 450)
  end

  subject(:result) { described_class.call(bake_day) }

  it "produit une ligne par variante vendue (quantité + CA net + coûtant)" do
    row = result.rows.find { |r| r.label == "Pain froment – 1 kg" }
    expect(row.qty).to eq(2)
    expect(row.sale_cents).to eq(1_100)
    expect(row.unit_price_cents).to eq(550)
    expect(row.unit_cost_cents).to eq(109)
    expect(row.cost_cents).to eq(218)
    expect(result.rows.map(&:label)).to include("Pain froment – 800 g")
  end

  it "réconcilie : Σ CA des lignes = CA du jour" do
    expect(result.total_sale_cents).to eq(1_550) # 550×2 + 450
    expect(result.total_sale_cents).to eq(result.day.revenue_cents)
  end

  it "expose le split authoritative (marge = boulangers + 4 Sources)" do
    day = result.day
    expect(day).to be_present
    expect(day.baker_pool_cents + day.four_sources_cents).to eq(day.gross_margin_cents)
  end

  it "utilise exactement les mêmes totaux que BakerRevenueService" do
    reference = BakerRevenueService.new(start_date: date, end_date: date).call.days.first
    expect(result.day.baker_pool_cents).to eq(reference.baker_pool_cents)
    expect(result.day.four_sources_cents).to eq(reference.four_sources_cents)
    expect(result.day.revenue_cents).to eq(reference.revenue_cents)
  end
end
