require "rails_helper"

RSpec.describe CustomerOriginReportService do
  let(:bake_day) { create(:bake_day) }
  let(:period) { { start_date: bake_day.baked_on - 1, end_date: bake_day.baked_on + 1 } }

  it "ventile les acheteurs par village, sans clients en double, et isole les non-renseignés" do
    godinne_a = create(:customer, locality: "Godinne")
    godinne_b = create(:customer, locality: "godinne")
    yvoir = create(:customer, locality: "Yvoir")
    unknown = create(:customer, locality: nil)

    create(:order, :paid, customer: godinne_a, bake_day: bake_day, total_cents: 1000)
    create(:order, :paid, customer: godinne_a, bake_day: bake_day, total_cents: 500)
    create(:order, :paid, customer: godinne_b, bake_day: bake_day, total_cents: 700)
    create(:order, :paid, customer: yvoir, bake_day: bake_day, total_cents: 300)
    create(:order, :paid, customer: unknown, bake_day: bake_day, total_cents: 900)
    # Hors assiette : commande annulée.
    create(:order, :cancelled, customer: yvoir, bake_day: bake_day, total_cents: 5000)

    report = described_class.new(**period).call

    godinne = report.rows.first
    expect(godinne.locality).to eq("Godinne")
    expect(godinne.customers_count).to eq(2)
    expect(godinne.orders_count).to eq(3)
    expect(godinne.revenue_cents).to eq(2200)

    expect(report.rows.map(&:locality)).to eq(%w[Godinne Yvoir])
    expect(report.rows.last.revenue_cents).to eq(300)
    expect(report.unknown.customers_count).to eq(1)
    expect(report.customers_count).to eq(4)
    expect(report.coverage_percent).to eq(75)
  end

  it "rend un rapport vide sans commande" do
    report = described_class.new(**period).call

    expect(report.rows).to be_empty
    expect(report.unknown).to be_nil
    expect(report.coverage_percent).to eq(0)
  end
end
