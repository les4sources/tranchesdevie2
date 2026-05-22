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
      expect(create(:order).paid_at).to be_nil
    end
  end
end
