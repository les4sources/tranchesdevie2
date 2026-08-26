require 'rails_helper'

RSpec.describe BreadBagPrice, type: :model do
  describe '.amount_cents_on' do
    it 'returns the amount of the most recent tier active on the given date' do
      create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 1, 1))
      create(:bread_bag_price, amount_cents: 6, active_from: Date.new(2026, 3, 1))

      expect(described_class.amount_cents_on(Date.new(2026, 2, 15))).to eq(4)
      expect(described_class.amount_cents_on(Date.new(2026, 3, 1))).to eq(6)
      expect(described_class.amount_cents_on(Date.new(2026, 4, 10))).to eq(6)
    end

    it 'is insensitive to tiers activated after the requested date (versioning)' do
      create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 1, 1))

      cost_before = described_class.amount_cents_on(Date.new(2026, 2, 1))
      create(:bread_bag_price, amount_cents: 9, active_from: Date.new(2026, 6, 1))

      expect(cost_before).to eq(4)
      expect(described_class.amount_cents_on(Date.new(2026, 2, 1))).to eq(4)
    end

    it 'returns nil when no tier is active on the date' do
      create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 3, 1))

      expect(described_class.amount_cents_on(Date.new(2026, 1, 1))).to be_nil
    end
  end

  describe 'validations' do
    it 'requires amount_cents and active_from' do
      price = described_class.new
      expect(price).not_to be_valid
      expect(price.errors[:amount_cents]).to be_present
      expect(price.errors[:active_from]).to be_present
    end
  end
end
