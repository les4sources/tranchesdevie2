require "rails_helper"

RSpec.describe BillingReportService do
  let(:month) { Date.new(2026, 5, 1) }
  let(:bake_day_in_month) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
  let(:bake_day_other_month) { create(:bake_day, baked_on: Date.new(2026, 6, 12)) }

  def report(customer: nil)
    described_class.new(month: month, customer: customer).call
  end

  it "regroupe les commandes des clients facturables pour le mois donné" do
    pro = create(:customer, billable: true, first_name: "Épicerie", last_name: "Durand")
    create(:order, :paid, :payment_paid, customer: pro, bake_day: bake_day_in_month, total_cents: 2000)
    create(:order, :unpaid, customer: pro, bake_day: bake_day_in_month, total_cents: 1500)

    result = report
    expect(result.customers.size).to eq(1)

    billing = result.customers.first
    expect(billing.customer).to eq(pro)
    expect(billing.orders.size).to eq(2)
    expect(billing.total_cents).to eq(3500)
    expect(billing.paid_total_cents).to eq(2000)
    expect(billing.unpaid_total_cents).to eq(1500)
  end

  it "agrège les totaux globaux du rapport" do
    pro = create(:customer, billable: true)
    create(:order, :paid, :payment_paid, customer: pro, bake_day: bake_day_in_month, total_cents: 2000)
    create(:order, :unpaid, customer: pro, bake_day: bake_day_in_month, total_cents: 1500)

    result = report
    expect(result.grand_total_cents).to eq(3500)
    expect(result.paid_total_cents).to eq(2000)
    expect(result.unpaid_total_cents).to eq(1500)
  end

  it "exclut les clients non facturables" do
    regular = create(:customer, billable: false)
    create(:order, :paid, customer: regular, bake_day: bake_day_in_month, total_cents: 2000)

    expect(report.customers).to be_empty
  end

  it "exclut les commandes hors du mois demandé" do
    pro = create(:customer, billable: true)
    create(:order, :paid, customer: pro, bake_day: bake_day_other_month, total_cents: 2000)

    expect(report.customers).to be_empty
  end

  it "exclut les statuts non facturables (annulée, planifiée, en attente)" do
    pro = create(:customer, billable: true)
    create(:order, :cancelled, customer: pro, bake_day: bake_day_in_month, total_cents: 2000)
    create(:order, :planned, customer: pro, bake_day: bake_day_in_month, total_cents: 2000)
    create(:order, :pending, customer: pro, bake_day: bake_day_in_month, total_cents: 2000)

    expect(report.customers).to be_empty
  end

  it "ne renvoie que le client demandé lorsqu'un filtre client est fourni" do
    pro_a = create(:customer, billable: true)
    pro_b = create(:customer, billable: true)
    create(:order, :paid, customer: pro_a, bake_day: bake_day_in_month, total_cents: 2000)
    create(:order, :paid, customer: pro_b, bake_day: bake_day_in_month, total_cents: 3000)

    result = report(customer: pro_a)
    expect(result.customers.size).to eq(1)
    expect(result.customers.first.customer).to eq(pro_a)
    expect(result.grand_total_cents).to eq(2000)
  end

  it "trie les commandes d'un client par date de cuisson" do
    pro = create(:customer, billable: true)
    later = create(:bake_day, baked_on: Date.new(2026, 5, 26))
    earlier = create(:bake_day, baked_on: Date.new(2026, 5, 5))
    create(:order, :paid, customer: pro, bake_day: later, total_cents: 1000)
    create(:order, :paid, customer: pro, bake_day: earlier, total_cents: 1000)

    baked_dates = report.customers.first.orders.map { |o| o.bake_day.baked_on }
    expect(baked_dates).to eq([ earlier.baked_on, later.baked_on ])
  end

  describe "récapitulatif par produit" do
    let(:pro) { create(:customer, billable: true) }
    let(:product) { create(:product, name: "Pain froment") }
    let(:petit) { create(:product_variant, product: product, name: "Petit 600 g") }
    let(:grand) { create(:product_variant, product: product, name: "Grand 1 kg") }

    def order_with(items, total_cents:)
      order = create(:order, :paid, customer: pro, bake_day: bake_day_in_month, total_cents: total_cents)
      items.each do |variant, qty, price|
        create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: price)
      end
      order
    end

    it "cumule les quantités par variante sur toutes les commandes du mois" do
      order_with([ [ petit, 2, 450 ], [ grand, 1, 700 ] ], total_cents: 1600)
      order_with([ [ petit, 3, 450 ] ], total_cents: 1350)

      lines = report.customers.first.product_lines
      expect(lines.map { |l| [ l.variant_name, l.unit_price_cents, l.qty, l.total_cents ] }).to eq([
        [ "Grand 1 kg", 700, 1, 700 ],
        [ "Petit 600 g", 450, 5, 2250 ]
      ])
      expect(lines.map(&:product_name).uniq).to eq([ "Pain froment" ])
    end

    it "sépare un même produit vendu à deux prix différents" do
      order_with([ [ petit, 2, 450 ] ], total_cents: 900)
      order_with([ [ petit, 1, 480 ] ], total_cents: 480)

      lines = report.customers.first.product_lines
      expect(lines.map { |l| [ l.unit_price_cents, l.qty ] }).to eq([ [ 450, 2 ], [ 480, 1 ] ])
    end

    it "expose la remise de groupe pour réconcilier avec le total" do
      order_with([ [ petit, 10, 450 ] ], total_cents: 4050)

      billing = report.customers.first
      expect(billing.gross_total_cents).to eq(4500)
      expect(billing.discount_cents).to eq(450)
      expect(billing.total_cents).to eq(4050)
    end
  end
end
