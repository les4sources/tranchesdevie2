require 'rails_helper'

RSpec.describe GroupDiscountService do
  let(:customer) { create(:customer) }
  let(:product) { create(:product) }
  let(:variant) { create(:product_variant, product: product, price_cents: 700) }
  let(:other_variant) { create(:product_variant, product: product, price_cents: 500) }

  def add_to_group(customer, group)
    create(:customer_group, customer: customer, group: group)
  end

  def lines(*pairs)
    pairs.map { |variant, qty| { variant: variant, qty: qty } }
  end

  describe '#total_discount_cents' do
    it 'is zero for a customer without groups' do
      service = described_class.new(customer)
      expect(service.total_discount_cents(lines([ variant, 2 ]))).to eq(0)
    end

    it 'applies the global percent for a group without targeted discounts (backward compatible)' do
      group = create(:group, discount_percent: 50)
      add_to_group(customer, group)
      service = described_class.new(customer)
      # 700*2 + 500*1 = 1900 → 50% → 950
      expect(service.total_discount_cents(lines([ variant, 2 ], [ other_variant, 1 ]))).to eq(950)
    end

    it 'lets a variant-specific fixed discount replace the global one (most specific wins)' do
      group = create(:group, discount_percent: 50)
      add_to_group(customer, group)
      # Variant: fixed reduction of 5,00 € (700 → 200) instead of 50% (350)
      create(:group_product_discount, :fixed, group: group, product_variant: variant, discount_value: 500)
      service = described_class.new(customer)
      # variant line: 2 * 500 reduction = 1000 ; other_variant: 50% of 500 = 250
      expect(service.total_discount_cents(lines([ variant, 2 ], [ other_variant, 1 ]))).to eq(1250)
    end

    it 'prefers a variant rule over a product rule' do
      group = create(:group, discount_percent: 0)
      add_to_group(customer, group)
      create(:group_product_discount, :fixed, group: group, product: product, discount_value: 100)
      create(:group_product_discount, :fixed, group: group, product_variant: variant, discount_value: 300)
      service = described_class.new(customer)
      # variant uses variant rule (300), other_variant uses product rule (100)
      expect(service.total_discount_cents(lines([ variant, 1 ], [ other_variant, 1 ]))).to eq(400)
    end

    it 'takes the best discount across multiple groups per line' do
      g1 = create(:group, discount_percent: 50)
      g2 = create(:group, discount_percent: 0)
      add_to_group(customer, g1)
      add_to_group(customer, g2)
      # g2 has a fixed 6,00 € reduction on the variant (600 > 350 from g1's 50%)
      create(:group_product_discount, :fixed, group: g2, product_variant: variant, discount_value: 600)
      service = described_class.new(customer)
      expect(service.unit_discount_cents(variant)).to eq(600)
    end
  end

  describe '#targeted_unit_discounts' do
    it 'only includes variants touched by a targeted rule' do
      group = create(:group, discount_percent: 50)
      add_to_group(customer, group)
      create(:group_product_discount, :fixed, group: group, product_variant: variant, discount_value: 500)
      service = described_class.new(customer)
      lookup = { variant.id => variant, other_variant.id => other_variant }
      expect(service.targeted_unit_discounts(lookup)).to eq(variant.id => 500)
    end
  end
end
