require "rails_helper"

RSpec.describe InvoiceBuilderService, type: :service do
  let(:customer) { create(:customer, billable: true) }
  let(:product) { create(:product) }
  let(:variant) { create(:product_variant, product: product, price_cents: 550) }

  def order_on(bake_day, status: :paid, qty: 1)
    create(:order, customer: customer, bake_day: bake_day, status: status, total_cents: 550 * qty).tap do |o|
      create(:order_item, order: o, product_variant: variant, qty: qty, unit_price_cents: 550)
    end
  end

  describe ".for_order" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:order) { order_on(bake_day, qty: 3) }

    it "crée une facture pour la commande" do
      expect { described_class.for_order(order) }.to change(Invoice, :count).by(1)
      expect(order.reload.invoices.count).to eq(1)
    end

    it "est idempotent : ne recrée pas une facture pour la même commande" do
      first = described_class.for_order(order)
      second = described_class.for_order(order)

      expect(second.id).to eq(first.id)
      expect(Invoice.count).to eq(1)
    end
  end

  describe ".for_customer_month" do
    let(:tuesday) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:friday) { create(:bake_day, baked_on: Date.new(2026, 5, 15)) }
    let(:other_month) { create(:bake_day, baked_on: Date.new(2026, 6, 2)) }

    before do
      order_on(tuesday, qty: 2)
      order_on(friday, qty: 1)
      order_on(other_month, qty: 5)            # hors période : ne doit pas compter
    end

    it "couvre uniquement les commandes facturables du mois" do
      invoice = described_class.for_customer_month(customer: customer, month: Date.new(2026, 5, 1))

      expect(invoice.orders.count).to eq(2)
      expect(invoice.total_cents).to eq(1100 + 550)
      expect(invoice).to be_period
    end

    it "renvoie nil si aucune commande sur la période" do
      empty_customer = create(:customer, billable: true)
      result = described_class.for_customer_month(customer: empty_customer, month: Date.new(2026, 5, 1))

      expect(result).to be_nil
    end
  end
end
