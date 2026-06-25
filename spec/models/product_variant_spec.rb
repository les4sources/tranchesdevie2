require 'rails_helper'

RSpec.describe ProductVariant, type: :model do
  # ISC-3: orderability reflects active flag + ProductAvailability windows.
  describe '#available_on?' do
    let(:product) { create(:product) }
    let(:date) { Date.current }

    it 'is false when the variant is inactive' do
      variant = create(:product_variant, :inactive, product: product)
      expect(variant.available_on?(date)).to be false
    end

    it 'is true when active with no availability windows defined' do
      variant = create(:product_variant, product: product)
      expect(variant.available_on?(date)).to be true
    end

    it 'is true when an availability window covers the date' do
      variant = create(:product_variant, product: product)
      variant.product_availabilities.create!(start_on: date - 1, end_on: date + 1)
      expect(variant.available_on?(date)).to be true
    end

    it 'is false when no availability window covers the date' do
      variant = create(:product_variant, product: product)
      variant.product_availabilities.create!(start_on: date + 5, end_on: date + 10)
      expect(variant.available_on?(date)).to be false
    end
  end

  # #90 : prix coûtant historisé par date d'activation.
  describe '#cost_price_cents' do
    let(:variant) { create(:product_variant) }

    it 'returns the amount of the most recent tier active on the given date' do
      create(:variant_cost_price, product_variant: variant, amount_cents: 67, active_from: Date.new(2026, 1, 1))
      create(:variant_cost_price, product_variant: variant, amount_cents: 80, active_from: Date.new(2026, 3, 1))

      expect(variant.cost_price_cents(on: Date.new(2026, 2, 15))).to eq(67)
      expect(variant.cost_price_cents(on: Date.new(2026, 3, 1))).to eq(80)
      expect(variant.cost_price_cents(on: Date.new(2026, 4, 10))).to eq(80)
    end

    it 'is insensitive to tiers activated after the requested date (versioning)' do
      create(:variant_cost_price, product_variant: variant, amount_cents: 67, active_from: Date.new(2026, 1, 1))

      cost_before = variant.cost_price_cents(on: Date.new(2026, 2, 1))
      create(:variant_cost_price, product_variant: variant, amount_cents: 99, active_from: Date.new(2026, 6, 1))

      expect(cost_before).to eq(67)
      expect(variant.cost_price_cents(on: Date.new(2026, 2, 1))).to eq(67)
    end

    it 'returns nil when no tier is active on the date (missing cost, not a misleading zero)' do
      create(:variant_cost_price, product_variant: variant, amount_cents: 67, active_from: Date.new(2026, 3, 1))

      expect(variant.cost_price_cents(on: Date.new(2026, 1, 1))).to be_nil
    end

    it 'returns nil when the variant has no cost price at all' do
      expect(variant.cost_price_cents(on: Date.current)).to be_nil
    end
  end

  describe '#cost_price_euros' do
    it 'converts the applicable cost from cents to euros, nil when missing' do
      variant = create(:product_variant)
      create(:variant_cost_price, product_variant: variant, amount_cents: 67, active_from: Date.new(2026, 1, 1))

      expect(variant.cost_price_euros(on: Date.new(2026, 2, 1))).to eq(0.67)
      expect(variant.cost_price_euros(on: Date.new(2025, 1, 1))).to be_nil
    end
  end
end
