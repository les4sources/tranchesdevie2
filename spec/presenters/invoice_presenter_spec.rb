require "rails_helper"

RSpec.describe InvoicePresenter do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, name: "Pain froment") }
  let(:variant) { create(:product_variant, product: product, name: "Petit 600 g", price_cents: 550) }

  def order_on(bake_day, qty:)
    create(:order, customer: customer, bake_day: bake_day, total_cents: 550 * qty).tap do |o|
      create(:order_item, order: o, product_variant: variant, qty: qty, unit_price_cents: 550)
    end
  end

  describe "lignes d'une facture commande unique" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:order) { order_on(bake_day, qty: 3) }
    let(:invoice) { InvoiceBuilderService.for_order(order) }

    it "expose le libellé produit + variante, quantité, prix et total" do
      line = described_class.new(invoice).lines.first

      expect(line.label).to eq("Pain froment — Petit 600 g")
      expect(line.quantity).to eq(3)
      expect(line.unit_price_cents).to eq(550)
      expect(line.total_cents).to eq(1650)
    end
  end

  describe "groupes par jour de cuisson (#27)" do
    let(:tuesday) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:friday) { create(:bake_day, baked_on: Date.new(2026, 5, 15)) }
    let!(:order_tue) { order_on(tuesday, qty: 2) }
    let!(:order_fri) { order_on(friday, qty: 1) }

    let(:invoice) do
      InvoiceBuilderService.for_customer_month(customer: customer, month: Date.new(2026, 5, 1))
    end

    it "regroupe les commandes par jour de cuisson, dans l'ordre chronologique" do
      groups = described_class.new(invoice).bake_day_groups

      expect(groups.map(&:baked_on)).to eq([ Date.new(2026, 5, 12), Date.new(2026, 5, 15) ])
      expect(groups.first.total_cents).to eq(1100)
      expect(groups.last.total_cents).to eq(550)
    end

    it "identifie chaque groupe par ses numéros de commande" do
      groups = described_class.new(invoice).bake_day_groups

      expect(groups.first.order_numbers).to include(order_tue.order_number)
      expect(groups.last.order_numbers).to include(order_fri.order_number)
    end
  end
end
