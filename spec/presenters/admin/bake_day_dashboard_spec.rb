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
end
