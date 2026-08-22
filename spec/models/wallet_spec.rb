require 'rails_helper'

RSpec.describe Wallet, type: :model do
  describe 'associations' do
    it { should belong_to(:customer) }
    it { should have_many(:wallet_transactions).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_numericality_of(:balance_cents).only_integer }
    it { should validate_numericality_of(:low_balance_threshold_cents).only_integer.is_greater_than_or_equal_to(0) }
  end

  describe '#credit!' do
    let(:wallet) { create(:wallet, balance_cents: 1000) }

    it 'increases the balance' do
      expect { wallet.credit!(500, type: :top_up) }
        .to change { wallet.balance_cents }.from(1000).to(1500)
    end

    it 'creates a wallet transaction' do
      expect { wallet.credit!(500, type: :top_up) }
        .to change { wallet.wallet_transactions.count }.by(1)
    end

    it 'records the transaction type' do
      wallet.credit!(500, type: :top_up)
      expect(wallet.wallet_transactions.last.top_up?).to be true
    end

    it 'records the stripe_payment_intent_id when provided' do
      wallet.credit!(500, type: :top_up, stripe_payment_intent_id: 'pi_test_123')
      expect(wallet.wallet_transactions.last.stripe_payment_intent_id).to eq('pi_test_123')
    end

    it 'records the description when provided' do
      wallet.credit!(500, type: :top_up, description: 'Test recharge')
      expect(wallet.wallet_transactions.last.description).to eq('Test recharge')
    end

    it 'can associate with an order' do
      order = create(:order)
      wallet.credit!(500, type: :order_refund, order: order)
      expect(wallet.wallet_transactions.last.order).to eq(order)
    end
  end

  describe '#debit!' do
    let(:wallet) { create(:wallet, balance_cents: 1000) }

    it 'decreases the balance' do
      expect { wallet.debit!(300, type: :order_debit) }
        .to change { wallet.balance_cents }.from(1000).to(700)
    end

    it 'creates a wallet transaction with negative amount' do
      wallet.debit!(300, type: :order_debit)
      expect(wallet.wallet_transactions.last.amount_cents).to eq(-300)
    end

    it 'allows negative balance (temporary)' do
      expect { wallet.debit!(1500, type: :order_debit) }
        .to change { wallet.balance_cents }.from(1000).to(-500)
    end
  end

  describe '#can_cover?' do
    let(:wallet) { create(:wallet, balance_cents: 1000) }

    it 'returns true when balance is greater than amount' do
      expect(wallet.can_cover?(500)).to be true
    end

    it 'returns true when balance equals amount' do
      expect(wallet.can_cover?(1000)).to be true
    end

    it 'returns false when balance is less than amount' do
      expect(wallet.can_cover?(1500)).to be false
    end

    it 'returns false when balance is negative' do
      wallet.update!(balance_cents: -100)
      expect(wallet.can_cover?(100)).to be false
    end
  end

  describe '#low_balance?' do
    it 'returns true when balance is below threshold' do
      wallet = create(:wallet, balance_cents: 500, low_balance_threshold_cents: 1000)
      expect(wallet.low_balance?).to be true
    end

    it 'returns false when balance equals threshold' do
      wallet = create(:wallet, balance_cents: 1000, low_balance_threshold_cents: 1000)
      expect(wallet.low_balance?).to be false
    end

    it 'returns false when balance is above threshold' do
      wallet = create(:wallet, balance_cents: 2000, low_balance_threshold_cents: 1000)
      expect(wallet.low_balance?).to be false
    end
  end

  describe '#balance_euros' do
    it 'returns the balance in euros' do
      wallet = create(:wallet, balance_cents: 1550)
      expect(wallet.balance_euros).to eq(15.50)
    end
  end
end
