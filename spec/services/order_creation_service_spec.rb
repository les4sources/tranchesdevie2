require "rails_helper"

# Order total reflects group discounts, including targeted ones (#87).
RSpec.describe OrderCreationService do
  let(:product) { create(:product, channel: "store") }
  let(:variant) { create(:product_variant, product: product, channel: "store", price_cents: 700) }
  let(:bake_day) { create(:bake_day, :tuesday, cut_off_at: 2.days.from_now) }

  def cart_for(variant, qty)
    [ { "product_variant_id" => variant.id.to_s, "qty" => qty } ]
  end

  def build_order(customer)
    described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant, 2), skip_capacity_check: true
    ).call
  end

  it "applies no discount for a customer without a group" do
    order = build_order(create(:customer))
    expect(order).to be_a(Order)
    expect(order.total_cents).to eq(1400)
  end

  it "applies the global percent for a plain group (backward compatible)" do
    customer = create(:customer)
    group = create(:group, discount_percent: 50)
    create(:customer_group, customer: customer, group: group)

    order = build_order(customer)
    # 1400 - 50% = 700
    expect(order.total_cents).to eq(700)
  end

  it "applies a targeted fixed discount instead of the global percent" do
    customer = create(:customer)
    group = create(:group, discount_percent: 50)
    create(:customer_group, customer: customer, group: group)
    create(:group_product_discount, :fixed, group: group, product_variant: variant, discount_value: 500)

    order = build_order(customer)
    # 2 units, 5,00 € off each → 1400 - 1000 = 400 (better than the 50% = 700)
    expect(order.total_cents).to eq(400)
  end
end

# ISC-86 : garde-fou de commande pour les variantes restreintes à certains jours de cuisson.
RSpec.describe OrderCreationService do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, channel: "store") }
  let(:friday) { Date.current.next_occurring(:friday) }
  let(:bake_day) { create(:bake_day, baked_on: friday, cut_off_at: 2.days.from_now) }

  def cart_for(variant)
    [ { "product_variant_id" => variant.id.to_s, "qty" => 1 } ]
  end

  it "rejects a variant not available on the bake day weekday" do
    variant = create(:product_variant, :tuesday_only, product: product)
    service = described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant), skip_capacity_check: true
    )

    expect(service.call).to be false
    expect(service.errors.join).to include("n'est pas disponible le vendredi")
  end

  it "accepts a variant available on the bake day weekday" do
    variant = create(:product_variant, :friday_only, product: product)
    service = described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant), skip_capacity_check: true
    )

    expect(service.call).to be_a(Order)
    expect(service.errors).to be_empty
  end

  it "accepts an unrestricted variant on any bake day weekday" do
    variant = create(:product_variant, product: product)
    service = described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant), skip_capacity_check: true
    )

    expect(service.call).to be_a(Order)
  end
end

# #99 : le nom du groupe « 4 Sources » est persisté sur la commande.
RSpec.describe OrderCreationService do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:variant) { create(:product_variant) } # active, canal "store"
  let(:cart_items) { [ { "product_variant_id" => variant.id, "qty" => 1 } ] }

  def build_service(group_name: nil)
    described_class.new(
      customer: customer,
      bake_day: bake_day,
      cart_items: cart_items,
      payment_method: "cash",
      skip_capacity_check: true,
      group_name: group_name
    )
  end

  it "persists the group name on the order when provided" do
    order = build_service(group_name: "Groupe de Joséphine").call

    expect(order).to be_a(Order)
    expect(order.group_name).to eq("Groupe de Joséphine")
  end

  it "stores nil when the group name is blank" do
    order = build_service(group_name: "   ").call

    expect(order.group_name).to be_nil
  end

  it "stores nil when no group name is provided" do
    order = build_service.call

    expect(order.group_name).to be_nil
  end
end
