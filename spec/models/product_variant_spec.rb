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

    it 'is false on a weekday excluded by the variant restriction' do
      variant = create(:product_variant, :friday_only, product: product)
      tuesday = Date.current.next_occurring(:tuesday)
      expect(variant.available_on?(tuesday)).to be false
    end

    it 'is true on a weekday allowed by the variant restriction' do
      variant = create(:product_variant, :friday_only, product: product)
      friday = Date.current.next_occurring(:friday)
      expect(variant.available_on?(friday)).to be true
    end
  end

  # ISC-86: variantes restreintes à certains jours de cuisson.
  describe 'weekday restriction (#86)' do
    let(:product) { create(:product) }

    describe '#available_weekdays=' do
      it 'drops blank values coming from the form and stores sorted integers' do
        variant = build(:product_variant, product: product)
        variant.available_weekdays = [ "5", "", "2", "2" ]
        expect(variant.available_weekdays).to eq([ 2, 5 ])
      end

      it 'treats an all-blank submission as no restriction' do
        variant = build(:product_variant, :friday_only, product: product)
        variant.available_weekdays = [ "" ]
        expect(variant.available_weekdays).to eq([])
        expect(variant.restricted_to_weekdays?).to be false
      end
    end

    describe '#available_on_weekday?' do
      it 'is available every cooking day when unrestricted' do
        variant = create(:product_variant, product: product)
        expect(BakeDay::COOKING_WDAYS).to all(satisfy { |wday| variant.available_on_weekday?(wday) })
      end

      it 'honours the restriction' do
        variant = create(:product_variant, :tuesday_only, product: product)
        expect(variant.available_on_weekday?(2)).to be true
        expect(variant.available_on_weekday?(5)).to be false
      end
    end

    describe '.available_on_weekday scope' do
      it 'returns unrestricted variants plus those allowing the weekday' do
        unrestricted = create(:product_variant, product: product)
        tuesday = create(:product_variant, :tuesday_only, product: product)
        friday = create(:product_variant, :friday_only, product: product)

        result = ProductVariant.available_on_weekday(2)
        expect(result).to include(unrestricted, tuesday)
        expect(result).not_to include(friday)
      end
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
