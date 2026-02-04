require 'rails_helper'

RSpec.describe WalletService do
  describe '.top_up' do
    let(:wallet) { create(:wallet, balance_cents: 1000) }

    it 'credits the wallet with the specified amount' do
      expect { WalletService.top_up(wallet: wallet, amount_cents: 2000, stripe_payment_intent_id: 'pi_123') }
        .to change { wallet.balance_cents }.from(1000).to(3000)
    end

    it 'creates a transaction of type top_up' do
      WalletService.top_up(wallet: wallet, amount_cents: 2000, stripe_payment_intent_id: 'pi_123')
      expect(wallet.wallet_transactions.last.top_up?).to be true
    end

    it 'stores the stripe_payment_intent_id' do
      WalletService.top_up(wallet: wallet, amount_cents: 2000, stripe_payment_intent_id: 'pi_123')
      expect(wallet.wallet_transactions.last.stripe_payment_intent_id).to eq('pi_123')
    end

    it 'creates a description with the amount in euros' do
      WalletService.top_up(wallet: wallet, amount_cents: 2000, stripe_payment_intent_id: 'pi_123')
      expect(wallet.wallet_transactions.last.description).to include('20.0')
    end
  end

  describe '.debit_for_order' do
    let(:wallet) { create(:wallet, balance_cents: 5000) }
    let(:order) { create(:order, total_cents: 1100) }

    it 'debits the order total from the wallet' do
      expect { WalletService.debit_for_order(wallet: wallet, order: order) }
        .to change { wallet.balance_cents }.from(5000).to(3900)
    end

    it 'creates a transaction of type order_debit' do
      WalletService.debit_for_order(wallet: wallet, order: order)
      expect(wallet.wallet_transactions.last.order_debit?).to be true
    end

    it 'associates the transaction with the order' do
      WalletService.debit_for_order(wallet: wallet, order: order)
      expect(wallet.wallet_transactions.last.order).to eq(order)
    end

    it 'includes the order number in the description' do
      WalletService.debit_for_order(wallet: wallet, order: order)
      expect(wallet.wallet_transactions.last.description).to include(order.order_number)
    end
  end

  describe '.refund_for_order' do
    let(:wallet) { create(:wallet, balance_cents: 3000) }
    let(:order) { create(:order, total_cents: 1100) }

    it 'credits the order total back to the wallet' do
      expect { WalletService.refund_for_order(wallet: wallet, order: order) }
        .to change { wallet.balance_cents }.from(3000).to(4100)
    end

    it 'creates a transaction of type order_refund' do
      WalletService.refund_for_order(wallet: wallet, order: order)
      expect(wallet.wallet_transactions.last.order_refund?).to be true
    end

    it 'associates the transaction with the order' do
      WalletService.refund_for_order(wallet: wallet, order: order)
      expect(wallet.wallet_transactions.last.order).to eq(order)
    end

    it 'includes the order number in the description' do
      WalletService.refund_for_order(wallet: wallet, order: order)
      expect(wallet.wallet_transactions.last.description).to include(order.order_number)
    end
  end
end
