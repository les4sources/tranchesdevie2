require 'rails_helper'

RSpec.describe Admin::BakeDayDashboard do
  let(:bake_day) { create(:bake_day) }
  let(:customer) { create(:customer) }
  let(:product) { create(:product, :bread) }
  let(:variant) { create(:product_variant, product: product, price_cents: 550) }

  subject(:dashboard) { described_class.new(bake_day) }

  # A confirmed (paid) order that must be counted everywhere.
  let!(:paid_order) do
    create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1100).tap do |order|
      create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 550)
    end
  end

  # A cancelled order that must be ignored by production-quantity calculations.
  let!(:cancelled_order) do
    create(:order, :cancelled, customer: customer, bake_day: bake_day, total_cents: 2200).tap do |order|
      create(:order_item, order: order, product_variant: variant, qty: 4, unit_price_cents: 550)
    end
  end

  describe '#variant_stats' do
    it 'excludes cancelled orders from the unit and order counts' do
      stat = dashboard.variant_stats.find { |s| s[:variant] == variant }

      expect(stat[:units_count]).to eq(2)
      expect(stat[:orders_count]).to eq(1)
    end
  end

  describe '#kpis' do
    it 'excludes cancelled orders from the headline counts' do
      kpis = dashboard.kpis

      expect(kpis[:orders_count]).to eq(1)
      expect(kpis[:items_count]).to eq(2)
      expect(kpis[:revenue_cents]).to eq(1100)
    end
  end

  describe '#customer_breakdown' do
    it 'excludes cancelled orders from the per-customer quantities' do
      entry = dashboard.customer_breakdown.find { |e| e[:customer] == customer }

      total_qty = entry[:orders].flat_map { |o| o[:items] }.sum { |i| i[:qty] }
      expect(total_qty).to eq(2)
      expect(entry[:total_cents]).to eq(1100)
    end
  end

  # ISC-88 : la panification utilise le ratio par farine, et expose deux totaux
  # de levain distincts (froment / seigle).
  describe '#dough_quantities' do
    let(:froment) { create(:flour, name: "Froment T65", flour_ratio: 0.5, water_ratio: 0.6, salt_ratio: 0.02, levain_ratio: 0.10) }
    let(:seigle) { create(:flour, :seigle, name: "Seigle T130", flour_ratio: 0.5, water_ratio: 0.8, salt_ratio: 0.03, levain_ratio: 0.20) }

    let(:bread_froment) do
      create(:product, :bread).tap { |p| create(:product_flour, product: p, flour: froment, percentage: 100) }
    end
    let(:bread_seigle) do
      create(:product, :bread).tap { |p| create(:product_flour, product: p, flour: seigle, percentage: 100) }
    end
    let(:variant_froment) { create(:product_variant, product: bread_froment, flour_quantity: 1000) }
    let(:variant_seigle) { create(:product_variant, product: bread_seigle, flour_quantity: 1000) }

    let!(:dough_order) do
      create(:order, :paid, customer: customer, bake_day: bake_day).tap do |o|
        create(:order_item, order: o, product_variant: variant_froment, qty: 1, unit_price_cents: 550)
        create(:order_item, order: o, product_variant: variant_seigle, qty: 1, unit_price_cents: 550)
      end
    end

    it "uses each flour's own ratio for the panification table" do
      data = dashboard.dough_quantities
      froment_col = data[:per_flour].find { |c| c[:flour] == froment }
      seigle_col = data[:per_flour].find { |c| c[:flour] == seigle }

      expect(froment_col[:levain_kg]).to eq(0.1)  # 1000 g pâte * 0.10 / 1000
      expect(seigle_col[:levain_kg]).to eq(0.2)   # 1000 g pâte * 0.20 / 1000
    end

    it 'splits the levain totals by type (base for #83)' do
      data = dashboard.dough_quantities
      expect(data[:levain_by_type]["froment"]).to eq(0.1)
      expect(data[:levain_by_type]["seigle"]).to eq(0.2)
    end
  end

  # Les commandes party (bake_day: nil, datées par leur party_event) doivent
  # compter dans les quantités de production du jour de cuisson correspondant.
  describe 'party orders held on the bake day' do
    let(:patons) { create(:flour, name: "Froment (pâtons)", flour_ratio: 0.5, water_ratio: 0.6, salt_ratio: 0.02, levain_ratio: 0.10) }
    let(:pizza_product) do
      create(:product, category: :dough_balls).tap { |p| create(:product_flour, product: p, flour: patons, percentage: 100) }
    end
    let(:pizza_variant) { create(:product_variant, product: pizza_product, flour_quantity: 250) }
    let(:party_event) { create(:party_event, kind: :private_party, slot: :soir, title: nil, capacity: nil, registration_closes_at: nil, held_on: bake_day.baked_on) }

    let!(:party_order) do
      create(:order, :paid, customer: customer, bake_day: nil, source: :party, party_event: party_event).tap do |o|
        create(:order_item, order: o, product_variant: pizza_variant, qty: 14, unit_price_cents: 500)
      end
    end

    it 'includes the party dough in the flour type stats' do
      stat = dashboard.flour_type_stats.find { |s| s[:flour] == patons }

      expect(stat).to be_present
      expect(stat[:flour_quantity]).to eq(14 * 250)
    end

    it 'ignores party orders held on another date' do
      party_event.update!(held_on: bake_day.baked_on + 7)

      expect(dashboard.flour_type_stats.find { |s| s[:flour] == patons }).to be_nil
    end

    it 'keeps party revenue out of the bake day KPIs' do
      expect(dashboard.kpis[:revenue_cents]).to eq(1100)
    end
  end
end
