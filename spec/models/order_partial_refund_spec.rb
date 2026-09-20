require 'rails_helper'

# Le remboursement partiel vu depuis la commande (#remboursement-partiel) :
# plafond, quantités déjà rendues, et sa place dans le reporting.
RSpec.describe Order, 'remboursement partiel' do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 9, 18)) }
  let(:order) { create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 1_650) }
  let!(:item) { create(:order_item, order: order, qty: 3, unit_price_cents: 550) }

  before { order.update!(payment_status: :paid) }

  it 'ne se rembourse pas si rien n\'a été encaissé' do
    order.update!(payment_status: :unpaid)

    expect(order.can_be_partially_refunded?).to be(false)
    expect(order.refundable_remaining_cents).to eq(0)
  end

  it 'décompte du remboursable ce qui est déjà rendu' do
    create(:partial_refund, order: order, amount_cents: 550)

    expect(order.reload.refundable_remaining_cents).to eq(1_100)
    expect(order.partially_refunded?).to be(true)
  end

  it 'ferme la porte quand tout a été rendu' do
    create(:partial_refund, order: order, amount_cents: 1_650)

    expect(order.reload.can_be_partially_refunded?).to be(false)
  end

  it 'compte les quantités déjà remboursées par ligne' do
    refund = create(:partial_refund, order: order, amount_cents: 1_100)
    create(:partial_refund_item, partial_refund: refund, order_item: item, qty: 2, amount_cents: 1_100)

    expect(order.reload.refunded_qty_by_item).to eq({ item.id => 2 })
  end

  describe '#can_report_issue_by_customer?' do
    it 'ouvre la fenêtre sur une commande retirée récemment' do
      expect(order.can_report_issue_by_customer?).to be(true)
    end

    it 'la referme au-delà de deux semaines' do
      order.bake_day.update!(baked_on: 3.weeks.ago.to_date)

      expect(order.reload.can_report_issue_by_customer?).to be(false)
    end

    it 'la garde fermée avant le jour de la fournée' do
      order.bake_day.update!(baked_on: 3.days.from_now.to_date)

      expect(order.reload.can_report_issue_by_customer?).to be(false)
    end

    it 'la garde fermée sur une commande annulée' do
      order.update!(status: :cancelled)

      expect(order.can_report_issue_by_customer?).to be(false)
    end
  end

  describe 'reporting des remboursements' do
    let(:range_start) { Date.new(2026, 9, 1) }
    let(:range_end) { Date.new(2026, 9, 30) }

    it 'fait apparaître le remboursement partiel dans le résumé' do
      create(:partial_refund, order: order, amount_cents: 550, channel: :wallet)

      summary = described_class.refunds_summary_between(range_start, range_end)

      expect(summary[:partial][:count]).to eq(1)
      expect(summary[:partial][:amount_cents]).to eq(550)
      expect(summary[:amount_cents]).to eq(550)
      expect(summary[:count]).to eq(1)
    end

    it 'le fait apparaître dans le détail, avec son canal' do
      create(:partial_refund, order: order, amount_cents: 550, channel: :cash, reason: "Pain manquant")

      details = described_class.detailed_refunds_between(range_start, range_end)

      expect(details.size).to eq(1)
      expect(details.first[:source]).to eq(:partiel_cash)
      expect(details.first[:amount_cents]).to eq(550)
      expect(details.first[:reason]).to eq("Pain manquant")
    end

    it 'laisse le CA intact : la commande reste vendue' do
      create(:partial_refund, order: order, amount_cents: 550)

      expect(described_class.revenue_between(range_start, range_end)).to eq(1_650)
    end
  end
end
