require 'rails_helper'

RSpec.describe RefundService do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }

  describe '#call for a wallet-paid order' do
    # Commande checkout réglée au portefeuille : pas de Payment Stripe. Avant le
    # branchement portefeuille, RefundService plantait sur @order.payment (nil).
    let!(:wallet) { create(:wallet, customer: customer, balance_cents: 5_000) }
    let(:order) { create(:order, :pending, customer: customer, bake_day: bake_day, total_cents: 1_100) }

    before { WalletCheckoutService.call(order: order) } # débite le portefeuille, passe à paid

    it 'recrédite le portefeuille au lieu d\'appeler Stripe' do
      expect(Stripe::Refund).not_to receive(:create)
      expect { described_class.new(order).call }
        .to change { wallet.reload.balance_cents }.by(1_100)
    end

    it 'annule la commande et renvoie true' do
      allow(SmsService).to receive(:send_refund)
      expect(described_class.new(order).call).to be(true)
      expect(order.reload).to be_cancelled
    end

    it 'refuse un 2e remboursement (déjà remboursé)' do
      described_class.new(order.reload).call
      service = described_class.new(order.reload)
      # cut_off pas dépassé mais la commande est cancelled → « Order must be paid »
      # OU « already refunded » : dans les deux cas, pas de nouveau crédit.
      expect { service.call }.not_to change { wallet.reload.balance_cents }
      expect(service.call).to be(false)
    end
  end
end
