require 'rails_helper'

RSpec.describe Payment, type: :model do
  describe '#stripe_fee_euros' do
    it 'converts the fee from cents to euros' do
      expect(build(:payment, stripe_fee_cents: 123).stripe_fee_euros).to eq(1.23)
    end

    it 'is nil when the fee has not been recorded yet' do
      expect(build(:payment, stripe_fee_cents: nil).stripe_fee_euros).to be_nil
    end
  end

  describe '#stripe_fee_recorded?' do
    it 'is true once a fee (even zero) is stored' do
      expect(build(:payment, stripe_fee_cents: 0).stripe_fee_recorded?).to be(true)
      expect(build(:payment, stripe_fee_cents: 50).stripe_fee_recorded?).to be(true)
    end

    it 'is false when no fee is stored' do
      expect(build(:payment, stripe_fee_cents: nil).stripe_fee_recorded?).to be(false)
    end
  end
end
