require "rails_helper"

RSpec.describe Invoice, type: :model do
  describe "numérotation séquentielle" do
    it "attribue FAC-YYYY-NNNN en repartant de 0001 par année" do
      first = create(:invoice, issued_on: Date.new(2026, 3, 1))
      second = create(:invoice, issued_on: Date.new(2026, 9, 1))

      expect(first.number).to eq("FAC-2026-0001")
      expect(second.number).to eq("FAC-2026-0002")
    end

    it "réinitialise la séquence à chaque année civile" do
      create(:invoice, issued_on: Date.new(2026, 12, 31))
      next_year = create(:invoice, issued_on: Date.new(2027, 1, 2))

      expect(next_year.number).to eq("FAC-2027-0001")
    end

    it "garantit l'unicité du numéro" do
      existing = create(:invoice)
      dup = build(:invoice, number: existing.number)

      expect(dup).not_to be_valid
      expect(dup.errors[:number]).to be_present
    end
  end

  describe "montants HT / TVA / TTC" do
    let(:customer) { create(:customer) }
    let(:bake_day) { create(:bake_day) }

    def order_with_total(total_cents)
      create(:order, customer: customer, bake_day: bake_day, total_cents: total_cents)
    end

    it "avec un taux à 0 : HT == TTC, TVA nulle (ne bloque pas)" do
      invoice = described_class.build_for_order(order_with_total(1650), vat_rate: 0)

      expect(invoice.subtotal_cents).to eq(1650)
      expect(invoice.vat_cents).to eq(0)
      expect(invoice.total_cents).to eq(1650)
      expect(invoice).to be_valid
    end

    it "avec un taux > 0 : déduit HT et TVA depuis le TTC" do
      invoice = described_class.build_for_order(order_with_total(10_600), vat_rate: 6)

      # 10600 TTC à 6 % → HT = 10600 / 1.06 = 10000, TVA = 600
      expect(invoice.subtotal_cents).to eq(10_000)
      expect(invoice.vat_cents).to eq(600)
      expect(invoice.total_cents).to eq(10_600)
      expect(invoice).to be_vat_applied
    end
  end

  describe "cohérence de période" do
    it "refuse une période dont la fin précède le début" do
      invoice = build(:invoice, period_start: Date.new(2026, 5, 31), period_end: Date.new(2026, 5, 1))
      expect(invoice).not_to be_valid
    end

    it "distingue facture commande unique et facture de période" do
      single = build(:invoice)
      period = build(:invoice, :period)

      expect(single).to be_single_order
      expect(period).to be_period
    end
  end
end
