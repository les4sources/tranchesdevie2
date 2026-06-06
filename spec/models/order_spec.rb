require 'rails_helper'

RSpec.describe Order, type: :model do
  describe '#payment_received?' do
    it 'is true for statuses reached after collecting payment' do
      %i[paid ready picked_up no_show].each do |status|
        expect(build(:order, status: status).payment_received?).to be(true)
      end
    end

    it 'is false before payment is collected or once cancelled' do
      %i[pending planned unpaid cancelled].each do |status|
        expect(build(:order, status: status).payment_received?).to be(false)
      end
    end
  end

  describe '#payment_method' do
    it 'returns :stripe when a Stripe payment exists' do
      order = create(:order)
      create(:payment, order: order)

      expect(order.reload.payment_method).to eq(:stripe)
    end

    it 'returns :wallet when a wallet debit exists' do
      order = create(:order, :from_calendar)
      create(:wallet_transaction, :order_debit, order: order)

      expect(order.reload.payment_method).to eq(:wallet)
    end

    it 'returns nil when no payment trace exists' do
      expect(create(:order).payment_method).to be_nil
    end
  end

  describe '#payment_refunded?' do
    it 'is true when the Stripe payment is refunded' do
      order = create(:order, :cancelled)
      create(:payment, :refunded, order: order)

      expect(order.reload.payment_refunded?).to be(true)
    end

    it 'is true when a wallet refund transaction exists' do
      order = create(:order, :cancelled)
      create(:wallet_transaction, :order_refund, order: order)

      expect(order.reload.payment_refunded?).to be(true)
    end

    it 'is false for a successful payment' do
      order = create(:order)
      create(:payment, order: order)

      expect(order.reload.payment_refunded?).to be(false)
    end
  end

  describe '.stripe_fees_between' do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }

    it 'sums the Stripe fees of completed orders paid via Stripe in range' do
      order_a = create(:order, :paid, bake_day: bake_day, total_cents: 2000)
      order_b = create(:order, :ready, bake_day: bake_day, total_cents: 3000)
      create(:payment, order: order_a, stripe_fee_cents: 50)
      create(:payment, order: order_b, stripe_fee_cents: 75)

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(125)
    end

    it 'ignores fees not yet recorded (nil) and orders without a Stripe payment' do
      order_with_fee = create(:order, :paid, bake_day: bake_day)
      create(:payment, order: order_with_fee, stripe_fee_cents: 40)

      order_pending_fee = create(:order, :paid, bake_day: bake_day)
      create(:payment, order: order_pending_fee, stripe_fee_cents: nil)

      create(:order, :paid, bake_day: bake_day) # paiement portefeuille / hors ligne : pas de Payment

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(40)
    end

    it 'excludes orders outside the bake day range' do
      out_of_range = create(:order, :paid, bake_day: create(:bake_day, baked_on: Date.new(2026, 4, 1)))
      create(:payment, order: out_of_range, stripe_fee_cents: 99)

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(0)
    end

    it 'excludes non-completed orders' do
      cancelled = create(:order, :cancelled, bake_day: bake_day)
      create(:payment, :refunded, order: cancelled, stripe_fee_cents: 60)

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(0)
    end
  end

  describe '#paid_at' do
    it 'uses the Stripe payment timestamp' do
      order = create(:order)
      payment = create(:payment, order: order)

      expect(order.reload.paid_at).to be_within(1.second).of(payment.created_at)
    end

    it 'falls back to the wallet debit timestamp' do
      order = create(:order, :from_calendar)
      debit = create(:wallet_transaction, :order_debit, order: order)

      expect(order.reload.paid_at).to be_within(1.second).of(debit.created_at)
    end

    it 'is nil without any payment trace' do
      expect(create(:order, paid_at: nil).paid_at).to be_nil
    end

    it 'uses the stored value for offline payments without any trace' do
      paid_on = Time.zone.local(2026, 5, 12, 10, 0)
      order = create(:order, :unpaid, paid_at: paid_on)

      expect(order.paid_at).to be_within(1.second).of(paid_on)
    end

    it 'prefers the stored value over the derived payment timestamp' do
      stored = Time.zone.local(2026, 5, 1, 9, 0)
      order = create(:order, paid_at: stored)
      create(:payment, order: order)

      expect(order.reload.paid_at).to be_within(1.second).of(stored)
    end
  end

  describe '.sales_by_internal_category_between' do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:start_date) { Date.new(2026, 5, 1) }
    let(:end_date) { Date.new(2026, 5, 31) }

    let(:bakery_variant) do
      create(:product_variant, product: create(:product, internal_category: :boulangerie))
    end
    let(:grocery_variant) do
      create(:product_variant, product: create(:product, :epicerie))
    end

    it 'agrège le CA, les quantités et le nombre de commandes par catégorie interne' do
      order1 = create(:order, :paid, bake_day: bake_day)
      create(:order_item, order: order1, product_variant: bakery_variant, qty: 2, unit_price_cents: 500)
      create(:order_item, order: order1, product_variant: grocery_variant, qty: 1, unit_price_cents: 300)

      order2 = create(:order, :ready, bake_day: bake_day)
      create(:order_item, order: order2, product_variant: bakery_variant, qty: 3, unit_price_cents: 500)

      result = described_class.sales_by_internal_category_between(start_date, end_date)
      bakery = result.find { |entry| entry[:internal_category] == 'boulangerie' }
      grocery = result.find { |entry| entry[:internal_category] == 'epicerie' }

      expect(bakery[:total_cents]).to eq(2500) # (2 * 500) + (3 * 500)
      expect(bakery[:total_quantity]).to eq(5)
      expect(bakery[:orders_count]).to eq(2)

      expect(grocery[:total_cents]).to eq(300)
      expect(grocery[:total_quantity]).to eq(1)
      expect(grocery[:orders_count]).to eq(1)
    end

    it 'exclut les commandes non finalisées (annulées, impayées, planifiées)' do
      cancelled = create(:order, :cancelled, bake_day: bake_day)
      create(:order_item, order: cancelled, product_variant: bakery_variant, qty: 4, unit_price_cents: 500)

      result = described_class.sales_by_internal_category_between(start_date, end_date)
      expect(result).to be_empty
    end
  end
end
