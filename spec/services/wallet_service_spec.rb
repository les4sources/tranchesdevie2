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

    it 'returns the created transaction' do
      result = WalletService.top_up(wallet: wallet, amount_cents: 2000, stripe_payment_intent_id: 'pi_123')
      expect(result).to eq(wallet.wallet_transactions.last)
    end

    # Le webhook Stripe et la page de retour Bancontact créditent tous deux la
    # même recharge : le service doit rester idempotent (#159).
    describe 'idempotence sur le stripe_payment_intent_id' do
      def top_up!(pi_id = 'pi_dup')
        WalletService.top_up(wallet: wallet, amount_cents: 2000, stripe_payment_intent_id: pi_id)
      end

      it 'ne crédite le portefeuille qu\'une seule fois' do
        expect { 2.times { top_up! } }.to change { wallet.reload.balance_cents }.from(1000).to(3000)
      end

      it 'ne crée qu\'une seule transaction' do
        expect { 2.times { top_up! } }.to change(WalletTransaction, :count).by(1)
      end

      it 'retourne la transaction déjà existante au second appel' do
        expect(top_up!).to eq(top_up!)
      end

      # Course réelle : le check à l'intérieur du verrou ne voit pas encore la
      # ligne concurrente, c'est l'index unique en base qui tranche.
      it 'traite un ActiveRecord::RecordNotUnique comme « déjà traité »' do
        existing = wallet.credit!(2000, type: :top_up, stripe_payment_intent_id: 'pi_race')
        allow(WalletService).to receive(:existing_top_up).and_return(nil, existing)

        expect { top_up!('pi_race') }.not_to change { wallet.reload.balance_cents }
        expect(WalletTransaction.where(stripe_payment_intent_id: 'pi_race').count).to eq(1)
      end

      it 'retourne la transaction existante après un RecordNotUnique' do
        existing = wallet.credit!(2000, type: :top_up, stripe_payment_intent_id: 'pi_race')
        allow(WalletService).to receive(:existing_top_up).and_return(nil, existing)

        expect(top_up!('pi_race')).to eq(existing)
      end
    end

    context 'without a stripe_payment_intent_id' do
      it 'credits the wallet without deduplicating' do
        expect { 2.times { WalletService.top_up(wallet: wallet, amount_cents: 500, stripe_payment_intent_id: nil) } }
          .to change { wallet.reload.balance_cents }.from(1000).to(2000)
      end
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
