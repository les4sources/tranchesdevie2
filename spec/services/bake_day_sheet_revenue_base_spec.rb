require "rails_helper"

# L'assiette du CA de la feuille compta (#274) : quels statuts de commande
# comptent, et le fait que le tableau se réconcilie TOUJOURS avec la carte
# « CA total ».
#
# Ce fichier est le gardien de la définition de « une vente ». Si un statut
# change de camp, c'est ici que ça doit se voir et se décider.
RSpec.describe "Feuille compta — assiette du CA", type: :model do
  let(:date) { Date.new(2026, 5, 12) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }
  let(:customer) { create(:customer) }
  let(:product) { create(:product, category: :breads, internal_category: :boulangerie, name: "Pain froment") }
  let(:variant) { create(:product_variant, product: product, name: "1 kg", price_cents: 100) }

  # Une commande par statut, avec un montant DISTINCT : le total permet donc de
  # lire sans ambiguïté quels statuts ont été retenus.
  AMOUNTS = {
    unpaid: 1,
    paid: 2,
    ready: 4,
    picked_up: 8,
    no_show: 16,
    planned: 32,
    pending: 64,
    cancelled: 128
  }.freeze

  BILLABLE_TOTAL = 1 + 2 + 4 + 8 + 16 # 31 unités de 100 cents

  before do
    AMOUNTS.each do |status, units|
      order = create(:order, status, customer: customer, bake_day: bake_day, total_cents: units * 100)
      create(:order_item, order: order, product_variant: variant, qty: units, unit_price_cents: 100)
    end
  end

  subject(:sheet) { BakeDaySheetService.call(bake_day) }

  it "retient exactement les cinq statuts facturables et laisse les trois autres dehors" do
    expect(sheet.total_sale_cents).to eq(BILLABLE_TOTAL * 100)
  end

  it "compte les commandes livrées mais pas encore encaissées (unpaid, no_show)" do
    # Sans unpaid (1) ni no_show (16), le total tomberait à 14 unités.
    expect(sheet.total_sale_cents).to be > 14 * 100
  end

  it "laisse dehors planned, pending et cancelled" do
    excluded = AMOUNTS.values_at(:planned, :pending, :cancelled).sum * 100
    expect(sheet.total_sale_cents).to eq(AMOUNTS.values.sum * 100 - excluded)
  end

  it "se réconcilie avec la carte « CA total » du jour" do
    expect(sheet.total_sale_cents).to eq(sheet.day.revenue_cents)
    expect(sheet).to be_reconciled
  end

  it "expose la même assiette que Order.completed" do
    expect(Order::COMPLETED_STATUSES).to match_array(%w[unpaid paid ready picked_up no_show])
    expect(BillingReportService::BILLABLE_STATUSES).to eq(Order::COMPLETED_STATUSES)
  end

  describe "ventilation par moyen de paiement réellement enregistré" do
    it "somme exactement le CA du jour" do
      expect(sheet.settlement.total_cents).to eq(sheet.day.revenue_cents)
    end

    it "range les commandes sans trace de paiement dans « aucun paiement enregistré »" do
      # Aucune de ces commandes n'a de Payment Stripe ni de débit portefeuille.
      expect(sheet.settlement.stripe_cents).to eq(0)
      expect(sheet.settlement.wallet_cents).to eq(0)
      expect(sheet.settlement.untracked_cents).to eq(BILLABLE_TOTAL * 100)
    end

    it "isole une commande réglée par Stripe" do
      paid_order = Order.completed.find_by(total_cents: 200)
      create(:payment, order: paid_order, status: :succeeded)

      expect(sheet.settlement.stripe_cents).to eq(200)
      expect(sheet.settlement.untracked_cents).to eq((BILLABLE_TOTAL * 100) - 200)
    end
  end
end
