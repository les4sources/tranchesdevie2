require 'rails_helper'

RSpec.describe PartialRefundService do
  let(:customer) { create(:customer, email: "cliente@example.com") }
  let(:bake_day) { create(:bake_day, :can_order) }
  # Commande réelle du souci d'origine : 6 froments aux graines + 1 rond cuit sur
  # pierre + 1 noix-figue, tous à 5,50 €, soit 44,00 €.
  let(:order) { create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 4_400) }
  let!(:froment) { create(:order_item, order: order, qty: 6, unit_price_cents: 550) }
  let!(:rond) { create(:order_item, order: order, qty: 1, unit_price_cents: 550) }
  let!(:noix_figue) { create(:order_item, order: order, qty: 1, unit_price_cents: 550) }

  before do
    order.update!(payment_status: :paid)
    allow(SmsService).to receive(:send_partial_refund)
  end

  describe '.proposed_amount_cents' do
    it 'chiffre les lignes cochées au net, au prorata de la quantité' do
      amount = described_class.proposed_amount_cents(
        order, { froment.id => 1, rond.id => 1, noix_figue.id => 1 }
      )

      expect(amount).to eq(1_650)
    end

    it 'répartit la remise du client sur les lignes' do
      # Total ramené à 40 € (remise de 4 €) : la ligne froment pèse 6/8 du brut.
      order.update!(total_cents: 4_000)

      expect(described_class.proposed_amount_cents(order, { froment.id => 1 })).to eq(500)
    end
  end

  describe '#call sur le portefeuille' do
    let!(:wallet) { create(:wallet, customer: customer, balance_cents: 0) }

    it 'crédite le portefeuille du net des lignes et enregistre le détail' do
      service = described_class.new(
        order,
        lines: { froment.id => 1, rond.id => 1, noix_figue.id => 1 },
        channel: "wallet",
        reason: "Pains manquants au retrait"
      )

      expect(service.call).to be(true)
      expect(wallet.reload.balance_cents).to eq(1_650)
      expect(service.partial_refund.amount_cents).to eq(1_650)
      expect(service.partial_refund.partial_refund_items.sum(:amount_cents)).to eq(1_650)
      expect(service.partial_refund.wallet_transaction).to be_present
    end

    it 'laisse la commande livrée et payée' do
      described_class.new(order, lines: { rond.id => 1 }, channel: "wallet").call

      expect(order.reload).to be_ready
      expect(order).to be_payment_status_paid
      expect(order.payment_refunded?).to be(false)
      expect(order.partially_refunded?).to be(true)
    end

    it 'répartit un montant forcé sur les lignes cochées' do
      service = described_class.new(
        order,
        lines: { froment.id => 1, rond.id => 1 },
        channel: "wallet",
        amount_cents: 1_000
      )

      expect(service.call).to be(true)
      expect(service.partial_refund.amount_cents).to eq(1_000)
      expect(service.partial_refund.partial_refund_items.sum(:amount_cents)).to eq(1_000)
    end

    it 'refuse de rembourser deux fois la même unité' do
      described_class.new(order, lines: { rond.id => 1 }, channel: "wallet").call

      service = described_class.new(order.reload, lines: { rond.id => 1 }, channel: "wallet")
      expect(service.call).to be(false)
      expect(service.errors.join).to match(/remboursable/)
      expect(wallet.reload.balance_cents).to eq(550)
    end

    it 'refuse un montant supérieur au remboursable restant' do
      service = described_class.new(
        order, lines: { froment.id => 1 }, channel: "wallet", amount_cents: 5_000
      )

      expect(service.call).to be(false)
      expect(service.errors.join).to match(/supérieur au remboursable/)
    end

    it 'refuse une commande non encaissée' do
      order.update!(payment_status: :unpaid)

      service = described_class.new(order, lines: { rond.id => 1 }, channel: "wallet")
      expect(service.call).to be(false)
      expect(service.errors).to include("Cette commande n'est pas remboursable")
    end
  end

  describe '#call sur Stripe' do
    let!(:payment) { create(:payment, order: order) }

    it 'ne rembourse que le montant partiel' do
      expect(Stripe::Refund).to receive(:create)
        .with(hash_including(payment_intent: payment.stripe_payment_intent_id, amount: 550))
        .and_return(double(status: "succeeded", id: "re_123", failure_reason: nil))

      service = described_class.new(order, lines: { rond.id => 1 }, channel: "stripe")

      expect(service.call).to be(true)
      expect(service.partial_refund.stripe_refund_id).to eq("re_123")
      expect(payment.reload).to be_succeeded
    end

    it "n'enregistre rien si Stripe refuse" do
      allow(Stripe::Refund).to receive(:create).and_raise(Stripe::StripeError.new("carte expirée"))

      service = described_class.new(order, lines: { rond.id => 1 }, channel: "stripe")

      expect(service.call).to be(false)
      expect(order.reload.partial_refunds).to be_empty
      expect(service.errors.join).to match(/carte expirée/)
    end

    it 'refuse le canal Stripe sans paiement en ligne' do
      payment.destroy!

      service = described_class.new(order.reload, lines: { rond.id => 1 }, channel: "stripe")
      expect(service.call).to be(false)
      expect(service.errors).to include("Aucun paiement Stripe sur cette commande")
    end
  end

  describe '#call en liquide' do
    it "n'effectue aucun mouvement automatique mais garde la trace" do
      expect(Stripe::Refund).not_to receive(:create)

      service = described_class.new(order, lines: { rond.id => 1 }, channel: "cash")

      expect(service.call).to be(true)
      expect(service.partial_refund).to be_channel_cash
      expect(service.partial_refund.wallet_transaction).to be_nil
    end
  end

  describe 'signalement lié' do
    let(:issue) { create(:order_issue, order: order, customer: customer) }

    it 'clôt le signalement auquel il répond' do
      described_class.new(order, lines: { rond.id => 1 }, channel: "cash", order_issue: issue).call

      expect(issue.reload).to be_state_resolved
      expect(issue.partial_refunds.count).to eq(1)
    end
  end

  describe 'notification du client' do
    it 'prévient par e-mail et par SMS' do
      expect(OrderNotificationService).to receive(:send_partial_refund)

      described_class.new(order, lines: { rond.id => 1 }, channel: "cash").call
    end
  end
end
