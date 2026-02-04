require 'rails_helper'

RSpec.describe WalletTransaction, type: :model do
  describe 'associations' do
    it { should belong_to(:wallet) }
    it { should belong_to(:order).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:amount_cents) }
    it { should validate_presence_of(:transaction_type) }
  end

  describe 'enums' do
    it { should define_enum_for(:transaction_type).with_values(top_up: 0, order_debit: 1, order_refund: 2) }
  end

  describe 'scopes' do
    let(:wallet) { create(:wallet) }

    before do
      create(:wallet_transaction, wallet: wallet, transaction_type: :top_up, amount_cents: 1000)
      create(:wallet_transaction, wallet: wallet, transaction_type: :order_debit, amount_cents: -500)
      create(:wallet_transaction, wallet: wallet, transaction_type: :order_refund, amount_cents: 200)
    end

    it 'filters by top_up type' do
      expect(WalletTransaction.top_up.count).to eq(1)
    end

    it 'filters by order_debit type' do
      expect(WalletTransaction.order_debit.count).to eq(1)
    end

    it 'filters by order_refund type' do
      expect(WalletTransaction.order_refund.count).to eq(1)
    end
  end

  describe '#amount_euros' do
    it 'returns positive amounts in euros' do
      transaction = build(:wallet_transaction, amount_cents: 1550)
      expect(transaction.amount_euros).to eq(15.50)
    end

    it 'returns negative amounts in euros' do
      transaction = build(:wallet_transaction, amount_cents: -500)
      expect(transaction.amount_euros).to eq(-5.00)
    end
  end
end
