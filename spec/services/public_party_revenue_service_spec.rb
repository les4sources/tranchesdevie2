require "rails_helper"

# Barème parties PUBLIQUES confirmé par Michael (19/07/2026) :
#   boulangers = 70 % × (base_boulangers − coûtant)
#   4 Sources  = base_4S + 30 % × (base_boulangers − coûtant)
# base_boulangers = prix − base_4S. Réconcilie : bakers + 4S = prix − coûtant.
RSpec.describe PublicPartyRevenueService do
  let(:date) { Date.new(2026, 7, 21) }
  let(:bake_day) { create(:bake_day, baked_on: date) }
  let(:customer) { create(:customer) }
  let(:product) { create(:product, :pizza_party_public, name: "Pizza party publique") }
  let(:adulte) { create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300) }
  let(:enfant) { create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200) }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: date - 30)
    create(:variant_cost_price, product_variant: enfant, amount_cents: 26, active_from: date - 30)
  end

  def order_with(items)
    total = items.sum { |_variant, qty, price| qty * price }
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: total)
    items.each { |variant, qty, price| create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: price) }
    order.reload
  end

  it "calcule le barème adulte : boulangers 4,72 €, 4 Sources 5,02 €" do
    result = described_class.call([ order_with([ [ adulte, 1, 1_000 ] ]) ])

    expect(result.bakers_cents).to eq(472)
    expect(result.four_sources_cents).to eq(502)
    # réconcilie : 472 + 502 = 974 = 1000 − 26
    expect(result.distributed_cents).to eq(result.sale_cents - result.dough_cost_cents)
  end

  it "calcule le barème enfant : boulangers 2,62 €, 4 Sources 3,12 €" do
    result = described_class.call([ order_with([ [ enfant, 1, 600 ] ]) ])

    expect(result.bakers_cents).to eq(262)
    expect(result.four_sources_cents).to eq(312)
    expect(result.distributed_cents).to eq(result.sale_cents - result.dough_cost_cents)
  end

  it "agrège adulte + enfant sur une même commande" do
    result = described_class.call([ order_with([ [ adulte, 1, 1_000 ], [ enfant, 1, 600 ] ]) ])

    expect(result.persons).to eq(2)
    expect(result.sale_cents).to eq(1_600)
    expect(result.bakers_cents).to eq(472 + 262)
    expect(result.four_sources_cents).to eq(502 + 312)
  end

  it "ignore les commandes sans article party publique" do
    bread = create(:product, :bread)
    bread_variant = create(:product_variant, product: bread, price_cents: 550)

    result = described_class.call([ order_with([ [ bread_variant, 1, 550 ] ]) ])

    expect(result.persons).to eq(0)
    expect(result.bakers_cents).to eq(0)
    expect(result.four_sources_cents).to eq(0)
  end
end
