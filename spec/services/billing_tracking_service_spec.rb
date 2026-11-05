require "rails_helper"

RSpec.describe BillingTrackingService do
  let(:end_month) { Date.new(2026, 11, 1) }
  let(:pro) { create(:customer, billable: true, first_name: "Épicerie", last_name: "Durand") }

  def bake_day_on(date)
    create(:bake_day, baked_on: date)
  end

  def report
    described_class.new(end_month: end_month).call
  end

  it "couvre les 12 mois se terminant par le mois demandé" do
    months = report.months
    expect(months.size).to eq(12)
    expect(months.first).to eq(Date.new(2025, 12, 1))
    expect(months.last).to eq(Date.new(2026, 11, 1))
  end

  it "range chaque commande dans la case client × mois avec son état" do
    create(:order, :paid, :payment_paid, customer: pro, bake_day: bake_day_on(Date.new(2026, 3, 10)), total_cents: 2000)
    create(:order, :unpaid, customer: pro, bake_day: bake_day_on(Date.new(2026, 5, 12)), total_cents: 1500, invoice_status: :invoiced)
    create(:order, :unpaid, customer: pro, bake_day: bake_day_on(Date.new(2026, 6, 2)), total_cents: 900)

    row = report.rows.sole
    expect(row.customer).to eq(pro)
    expect(row.cells[Date.new(2026, 3, 1)].state).to eq(:paid)
    expect(row.cells[Date.new(2026, 5, 1)].state).to eq(:awaiting)
    expect(row.cells[Date.new(2026, 6, 1)].state).to eq(:to_invoice)
    expect(row.cells[Date.new(2026, 7, 1)].state).to eq(:empty)

    expect(row.total.total_cents).to eq(4400)
    expect(row.total.paid_cents).to eq(2000)
    expect(row.total.awaiting_cents).to eq(1500)
    expect(row.total.to_invoice_cents).to eq(900)
    expect(row.total.unpaid_cents).to eq(2400)
  end

  it "fait primer « à facturer » quand un mois mélange les états" do
    bake_day = bake_day_on(Date.new(2026, 9, 8))
    create(:order, :paid, :payment_paid, customer: pro, bake_day: bake_day, total_cents: 1000)
    create(:order, :unpaid, customer: pro, bake_day: bake_day, total_cents: 500)

    cell = report.rows.sole.cells[Date.new(2026, 9, 1)]
    expect(cell.orders_count).to eq(2)
    expect(cell.state).to eq(:to_invoice)
    expect(cell.to_invoice_cents).to eq(500)
  end

  it "totalise chaque mois sur tous les clients" do
    other = create(:customer, billable: true, first_name: "Zoé", last_name: "Martin")
    bake_day = bake_day_on(Date.new(2026, 10, 6))
    create(:order, :unpaid, customer: pro, bake_day: bake_day, total_cents: 1000)
    create(:order, :paid, :payment_paid, customer: other, bake_day: bake_day, total_cents: 700)

    result = report
    expect(result.rows.map(&:customer)).to contain_exactly(pro, other)
    expect(result.month_totals[Date.new(2026, 10, 1)].total_cents).to eq(1700)
    expect(result.grand_total.paid_cents).to eq(700)
  end

  it "exclut les clients non facturables, les commandes annulées et hors période" do
    regular = create(:customer, billable: false)
    create(:order, :unpaid, customer: regular, bake_day: bake_day_on(Date.new(2026, 10, 6)), total_cents: 1000)
    create(:order, :cancelled, customer: pro, bake_day: bake_day_on(Date.new(2026, 10, 9)), total_cents: 1000)
    create(:order, :unpaid, customer: pro, bake_day: bake_day_on(Date.new(2025, 11, 28)), total_cents: 1000)

    expect(report.rows).to be_empty
  end
end
