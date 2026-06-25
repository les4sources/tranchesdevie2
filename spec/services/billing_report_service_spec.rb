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
end
