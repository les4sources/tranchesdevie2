require 'rails_helper'

RSpec.describe WalletCheckoutService do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:order) { create(:order, :pending, customer: customer, bake_day: bake_day, total_cents: 1_100) }

  describe '.call' do
    context 'when the wallet has enough available balance' do
      let!(:wallet) { create(:wallet, customer: customer, balance_cents: 5_000) }

      it 'returns true' do
        expect(described_class.call(order: order)).to be(true)
      end

      it 'transitions the order to paid and stamps paid_at' do
        described_class.call(order: order)
        expect(order.reload).to be_paid
        expect(order.read_attribute(:paid_at)).to be_present
      end

      it 'debits the wallet by the order total' do
        expect { described_class.call(order: order) }
          .to change { wallet.reload.balance_cents }.from(5_000).to(3_900)
      end

      it 'records an order_debit wallet transaction linked to the order' do
        described_class.call(order: order)
        transaction = wallet.wallet_transactions.order_debit.last
        expect(transaction.order).to eq(order)
        expect(transaction.amount_cents).to eq(-1_100)
      end

      it 'drives the order payment_status to paid via the transaction hook' do
        described_class.call(order: order)
        expect(order.reload).to be_payment_status_paid
      end
    end

    context 'when the available balance is insufficient' do
      let!(:wallet) { create(:wallet, customer: customer, balance_cents: 500) }

      it 'returns false with an error and does not debit' do
        service = described_class.new(order)
        expect(service.call).to be(false)
        expect(service.error).to eq('Solde du portefeuille insuffisant')
        expect(wallet.reload.balance_cents).to eq(500)
      end

      it 'leaves the order pending and unpaid' do
        described_class.call(order: order)
        expect(order.reload).to be_pending
        expect(wallet.wallet_transactions.order_debit).to be_empty
      end
    end

    context 'when funds are committed to planned calendar orders' do
      let!(:wallet) { create(:wallet, customer: customer, balance_cents: 1_500) }
      # 1000 réservés à une commande planifiée → solde disponible 500 < 1100.
      let!(:planned) do
        create(:order, :planned, customer: customer, bake_day: create(:bake_day, :friday, :can_order), total_cents: 1_000)
      end

      it 'refuses because available balance (not raw balance) is checked' do
        service = described_class.new(order)
        expect(service.call).to be(false)
        expect(wallet.reload.balance_cents).to eq(1_500)
      end
    end

    context 'when the customer has no wallet' do
      it 'returns false with an explanatory error' do
        service = described_class.new(order)
        expect(service.call).to be(false)
        expect(service.error).to match(/portefeuille/i)
      end
    end
  end
end
