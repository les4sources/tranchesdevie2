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
end
