require 'rails_helper'

# Order total reflects group discounts, including targeted ones (#87).
RSpec.describe OrderCreationService do
  let(:product) { create(:product, channel: 'store') }
  let(:variant) { create(:product_variant, product: product, channel: 'store', price_cents: 700) }
  let(:bake_day) { create(:bake_day, :tuesday, cut_off_at: 2.days.from_now) }

  def cart_for(variant, qty)
    [ { "product_variant_id" => variant.id.to_s, "qty" => qty } ]
  end

  def build_order(customer)
    described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant, 2), skip_capacity_check: true
    ).call
  end

  it 'applies no discount for a customer without a group' do
    order = build_order(create(:customer))
    expect(order).to be_a(Order)
    expect(order.total_cents).to eq(1400)
  end

  it 'applies the global percent for a plain group (backward compatible)' do
    customer = create(:customer)
    group = create(:group, discount_percent: 50)
    create(:customer_group, customer: customer, group: group)

    order = build_order(customer)
    # 1400 - 50% = 700
    expect(order.total_cents).to eq(700)
  end

  it 'applies a targeted fixed discount instead of the global percent' do
    customer = create(:customer)
    group = create(:group, discount_percent: 50)
    create(:customer_group, customer: customer, group: group)
    create(:group_product_discount, :fixed, group: group, product_variant: variant, discount_value: 500)

    order = build_order(customer)
    # 2 units, 5,00 € off each → 1400 - 1000 = 400 (better than the 50% = 700)
    expect(order.total_cents).to eq(400)
  end
end
