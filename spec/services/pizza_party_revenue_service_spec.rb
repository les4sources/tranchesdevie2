require "rails_helper"

# Barème parties privées confirmé par Michael (19/07/2026) :
#   4 Sources  = N × (1 € + 30 % × 2 €) + 10 € forfait
#   Boulangers = N × (4 € − coûtant pâton − 30 % × 2 €) + 30 € forfait
RSpec.describe PizzaPartyRevenueService do
  let(:date) { Date.new(2026, 7, 21) }
  let(:bake_day) { create(:bake_day, baked_on: date) }
  let(:customer) { create(:customer) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée – Nombre de personnes") }
  let(:party_variant) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500) }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait Pizza party") }
  let(:forfait_variant) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4000) }

  def party_order(persons:, with_forfait: true, cost_cents: 26)
    create(:variant_cost_price, product_variant: party_variant, amount_cents: cost_cents, active_from: date - 30) if cost_cents
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: persons * 500 + (with_forfait ? 4000 : 0))
    create(:order_item, order: order, product_variant: party_variant, qty: persons, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait_variant, qty: 1, unit_price_cents: 4000) if with_forfait
    order.reload
  end

  describe "l'exemple de référence : 10 personnes, coûtant 0,26 €, forfait" do
    subject(:result) { described_class.call([ party_order(persons: 10) ]) }

    it "compte 10 personnes sur 1 commande" do
      expect(result.persons).to eq(10)
      expect(result.party_orders_count).to eq(1)
    end

    it "calcule un CA de 90 € (10×5 € + 40 € forfait)" do
      expect(result.sale_cents).to eq(9000)
    end

    it "calcule un coûtant de 2,60 € (10 × 0,26 €)" do
      expect(result.dough_cost_cents).to eq(260)
    end

    it "attribue 26 € aux 4 Sources (10 × 1,60 € + 10 € forfait)" do
      expect(result.four_sources_cents).to eq(2600)
    end

    it "attribue 61,40 € aux boulangers (10 × 3,14 € + 30 € forfait)" do
      expect(result.bakers_cents).to eq(6140)
    end

    it "réconcilie : part 4S + part boulangers = CA − coûtant" do
      expect(result.distributed_cents).to eq(result.sale_cents - result.dough_cost_cents)
    end
  end

  it "sans coûtant configuré, traite le coûtant du pâton comme 0" do
    result = described_class.call([ party_order(persons: 10, cost_cents: nil) ])
    # Boulangers = 10 × (4 − 0 − 0,60) + 30 = 3400 + 3000
    expect(result.bakers_cents).to eq(6400)
    expect(result.four_sources_cents).to eq(2600)
    expect(result.distributed_cents).to eq(result.sale_cents) # coûtant 0
  end

  it "n'applique le forfait (30/10) que si la commande porte la ligne forfait" do
    result = described_class.call([ party_order(persons: 4, with_forfait: false) ])
    # 4S = 4 × 1,60 = 6,40 € ; boulangers = 4 × 3,14 = 12,56 € ; pas de +10/+30
    expect(result.four_sources_cents).to eq(640)
    expect(result.bakers_cents).to eq(1256)
  end

  it "ignore les commandes sans article party" do
    bread = create(:product, :bread)
    bread_variant = create(:product_variant, product: bread, price_cents: 550)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 550)
    create(:order_item, order: order, product_variant: bread_variant, qty: 1, unit_price_cents: 550)

    result = described_class.call([ order.reload ])
    expect(result.persons).to eq(0)
    expect(result.party_orders_count).to eq(0)
    expect(result.bakers_cents).to eq(0)
    expect(result.four_sources_cents).to eq(0)
  end

  it "agrège plusieurs commandes party" do
    result = described_class.call([ party_order(persons: 10), party_order(persons: 4) ])
    expect(result.persons).to eq(14)
    expect(result.party_orders_count).to eq(2)
    # 4S = 2600 + (4×160 + 1000) = 2600 + 1640 = 4240
    expect(result.four_sources_cents).to eq(4240)
  end
end
