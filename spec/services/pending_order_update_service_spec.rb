require "rails_helper"

# Mise à jour idempotente d'une commande pending existante (#124).
RSpec.describe PendingOrderUpdateService do
  let(:oven_capacity_grams) { 100_000 }
  let!(:production_setting) do
    ProductionSetting.create!(
      oven_capacity_grams: oven_capacity_grams,
      market_day_oven_capacity_grams: oven_capacity_grams * 2
    )
  end
  let!(:mold_type) { MoldType.create!(name: "Moule test", limit: 100, position: 1) }
  let!(:flour) { Flour.create!(name: "Farine test", kneader_limit_grams: 100_000, position: 1) }
  let!(:product) do
    create(:product, category: :breads, channel: "store").tap do |p|
      ProductFlour.create!(product: p, flour: flour, percentage: 100)
    end
  end
  let!(:variant) do
    create(:product_variant, product: product, channel: "store", price_cents: 550,
                             flour_quantity: 1_000, mold_type: mold_type)
  end
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:customer) { create(:customer) }

  # Commande pending initiale : 1 unité (550 cents).
  let!(:order) do
    o = create(:order, :pending, customer: customer, bake_day: bake_day, total_cents: 550, payment_intent_id: "pi_x")
    o.order_items.create!(product_variant: variant, qty: 1, unit_price_cents: 550)
    o
  end

  def cart(qty)
    [ { "product_variant_id" => variant.id, "qty" => qty } ]
  end

  it "réécrit les order_items et le total pour refléter le panier" do
    result = described_class.new(order: order, cart_items: cart(3)).call

    expect(result).to eq(order)
    order.reload
    expect(order.order_items.sum(:qty)).to eq(3)
    expect(order.total_cents).to eq(1650)
  end

  it "ne double-compte pas la propre réservation de la commande sur une fournée pleine" do
    # Four à 3000 g ; la commande réserve déjà 1000 g. La faire passer à 3 unités
    # (3000 g) doit passer car sa propre réservation est exclue du calcul.
    production_setting.update!(oven_capacity_grams: 3_000)

    result = described_class.new(order: order, cart_items: cart(3)).call
    expect(result).to eq(order)
    expect(order.reload.total_cents).to eq(1650)
  end

  it "rejette une vraie sur-réservation" do
    production_setting.update!(oven_capacity_grams: 3_000)

    service = described_class.new(order: order, cart_items: cart(4)) # 4000 g > 3000 g
    expect(service.call).to be false
    expect(service.errors.join).to include("Four")
    # La commande n'est pas modifiée en cas d'échec.
    expect(order.reload.order_items.sum(:qty)).to eq(1)
    expect(order.total_cents).to eq(550)
  end

  it "refuse un panier vide" do
    service = described_class.new(order: order, cart_items: [])
    expect(service.call).to be false
    expect(service.errors.join).to include("empty")
  end
end
