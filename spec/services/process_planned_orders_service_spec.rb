require 'rails_helper'

RSpec.describe ProcessPlannedOrdersService do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :cut_off_passed) }
  let(:wallet) { create(:wallet, customer: customer, balance_cents: 5000) }
  let(:product_variant) { create(:product_variant, price_cents: 550) }

  let!(:planned_order) do
    order = create(:order, :planned, customer: customer, bake_day: bake_day, source: :calendar, total_cents: 1100)
    create(:order_item, order: order, product_variant: product_variant, qty: 2, unit_price_cents: 550)
    order
  end

  before do
    # Ensure wallet exists
    wallet
  end

  describe '.process_for_bake_day' do
    it 'processes all planned orders for the bake day with send_sms: true when baked_on is still in the future' do
      expect(ProcessPlannedOrdersService).to receive(:process_order).with(planned_order, send_sms: true)
      ProcessPlannedOrdersService.process_for_bake_day(bake_day)
    end

    it 'only processes planned orders' do
      paid_order = create(:order, :paid, customer: customer, bake_day: bake_day)

      expect(ProcessPlannedOrdersService).to receive(:process_order).with(planned_order, send_sms: true)
      expect(ProcessPlannedOrdersService).not_to receive(:process_order).with(paid_order, anything)

      ProcessPlannedOrdersService.process_for_bake_day(bake_day)
    end

    it 'passes send_sms: false when the bake day is already in the past (stale catch-up)' do
      stale_bake_day = create(:bake_day, baked_on: Date.current - 1.day, cut_off_at: 3.days.ago)
      stale_order = create(:order, :planned, customer: customer, bake_day: stale_bake_day, source: :calendar, total_cents: 1100)

      expect(ProcessPlannedOrdersService).to receive(:process_order).with(stale_order, send_sms: false)
      ProcessPlannedOrdersService.process_for_bake_day(stale_bake_day)
    end
  end

  describe '.process_order' do
    context 'when wallet has sufficient balance' do
      it 'debits the wallet' do
        expect {
          ProcessPlannedOrdersService.process_order(planned_order)
        }.to change { wallet.reload.balance_cents }.from(5000).to(3900)
      end

      it 'transitions the order to paid' do
        ProcessPlannedOrdersService.process_order(planned_order)
        expect(planned_order.reload.paid?).to be true
      end

      it 'sends a confirmation SMS' do
        expect(SmsService).to receive(:send_planned_order_confirmed).with(planned_order)
        ProcessPlannedOrdersService.process_order(planned_order)
      end
    end

    context 'when wallet has insufficient balance' do
      before do
        wallet.update!(balance_cents: 500)
      end

      it 'does not debit the wallet' do
        expect {
          ProcessPlannedOrdersService.process_order(planned_order)
        }.not_to change { wallet.reload.balance_cents }
      end

      it 'cancels the order' do
        ProcessPlannedOrdersService.process_order(planned_order)
        expect(planned_order.reload.cancelled?).to be true
      end

      it 'sends a cancellation SMS' do
        expect(SmsService).to receive(:send_planned_order_cancelled).with(planned_order)
        ProcessPlannedOrdersService.process_order(planned_order)
      end
    end

    context 'when customer has no wallet' do
      before do
        wallet.destroy!
      end

      it 'cancels the order' do
        ProcessPlannedOrdersService.process_order(planned_order)
        expect(planned_order.reload.cancelled?).to be true
      end

      it 'sends a cancellation SMS' do
        expect(SmsService).to receive(:send_planned_order_cancelled).with(planned_order)
        ProcessPlannedOrdersService.process_order(planned_order)
      end
    end

    context 'low balance alert' do
      before do
        wallet.update!(balance_cents: 1500, low_balance_threshold_cents: 1000)
      end

      it 'sends low balance alert if balance drops below threshold' do
        expect(SmsService).to receive(:send_planned_order_confirmed).with(planned_order)
        expect(SmsService).to receive(:send_low_balance_alert).with(customer)

        ProcessPlannedOrdersService.process_order(planned_order)

        expect(wallet.reload.balance_cents).to eq(400)
      end
    end

    context 'when send_sms: false (stale catch-up)' do
      it 'still debits the wallet and marks the order paid but does not send confirmation SMS' do
        expect(SmsService).not_to receive(:send_planned_order_confirmed)
        expect(SmsService).not_to receive(:send_low_balance_alert)

        expect {
          ProcessPlannedOrdersService.process_order(planned_order, send_sms: false)
        }.to change { wallet.reload.balance_cents }.from(5000).to(3900)

        expect(planned_order.reload.paid?).to be true
      end

      it 'still cancels the order when balance insufficient but does not send cancellation SMS' do
        wallet.update!(balance_cents: 500)

        expect(SmsService).not_to receive(:send_planned_order_cancelled)

        ProcessPlannedOrdersService.process_order(planned_order, send_sms: false)

        expect(planned_order.reload.cancelled?).to be true
      end
    end
  end
end
