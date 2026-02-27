require 'rails_helper'

RSpec.describe 'Wallet and Calendar Flow', type: :request do
  let(:customer) { create(:customer, sms_opt_out: false) }
  let(:product_variant) { create(:product_variant, price_cents: 550) }

  before do
    # Stub SMS service
    allow(HTTParty).to receive(:post).and_return(
      double(success?: true, code: 200, :[] => 'msg_123', body: '{"messageid": "msg_123"}')
    )
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SMSTOOLS_CLIENT_ID').and_return('test_client_id')
    allow(ENV).to receive(:[]).with('SMSTOOLS_CLIENT_SECRET').and_return('test_client_secret')
    allow(ENV).to receive(:[]).with('SMSTOOLS_SENDER').and_return('TranchesDeVie')
  end

  describe 'complete flow: wallet reload + planned order + cut-off processing' do
    let(:bake_day) { create(:bake_day, :can_order, baked_on: Date.current + 3.days) }

    context 'when customer has sufficient balance' do
      before do
        # Create wallet with sufficient balance
        create(:wallet, customer: customer, balance_cents: 2000)  # 20€
      end

      it 'successfully processes the planned order at cut-off' do
        # 1. Create a planned order via the service
        result = PlannedOrderService.upsert(
          customer: customer,
          bake_day: bake_day,
          items: [{ product_variant_id: product_variant.id, qty: 2 }]
        )

        expect(result[:order]).to be_persisted
        expect(result[:order].planned?).to be true
        expect(result[:order].total_cents).to eq(1100)  # 2 * 550

        # 2. Simulate cut-off by processing the order
        ProcessPlannedOrdersService.process_order(result[:order])

        # 3. Verify the order is now paid
        result[:order].reload
        expect(result[:order].paid?).to be true

        # 4. Verify wallet was debited
        customer.wallet.reload
        expect(customer.wallet.balance_cents).to eq(900)  # 2000 - 1100

        # 5. Verify SMS was sent (confirmation)
        expect(SmsMessage.where(customer: customer, kind: :confirmation).count).to eq(1)
      end
    end

    context 'when customer has insufficient balance' do
      before do
        # Create wallet with insufficient balance
        create(:wallet, customer: customer, balance_cents: 500)  # 5€ (need 11€)
      end

      it 'cancels the order and sends cancellation SMS' do
        # 1. Create a planned order
        result = PlannedOrderService.upsert(
          customer: customer,
          bake_day: bake_day,
          items: [{ product_variant_id: product_variant.id, qty: 2 }]
        )

        expect(result[:order]).to be_persisted
        expect(result[:order].planned?).to be true

        # 2. Simulate cut-off by processing the order
        ProcessPlannedOrdersService.process_order(result[:order])

        # 3. Verify the order is cancelled
        result[:order].reload
        expect(result[:order].cancelled?).to be true

        # 4. Verify wallet was NOT debited
        customer.wallet.reload
        expect(customer.wallet.balance_cents).to eq(500)

        # 5. Verify cancellation SMS was sent
        expect(SmsMessage.where(customer: customer, kind: :other).count).to eq(1)
      end
    end

    context 'when customer has no wallet' do
      it 'cancels the order' do
        # 1. Create a planned order (customer has no wallet)
        result = PlannedOrderService.upsert(
          customer: customer,
          bake_day: bake_day,
          items: [{ product_variant_id: product_variant.id, qty: 2 }]
        )

        # 2. Process the order
        ProcessPlannedOrdersService.process_order(result[:order])

        # 3. Verify the order is cancelled
        result[:order].reload
        expect(result[:order].cancelled?).to be true
      end
    end
  end

  describe 'modifying planned orders before cut-off' do
    let(:bake_day) { create(:bake_day, :can_order) }
    let(:product_variant_2) { create(:product_variant, price_cents: 800) }

    before do
      create(:wallet, customer: customer, balance_cents: 5000)
    end

    it 'allows updating items on a planned order' do
      # Create initial order with 2 items
      result = PlannedOrderService.upsert(
        customer: customer,
        bake_day: bake_day,
        items: [{ product_variant_id: product_variant.id, qty: 2 }]
      )

      order = result[:order]
      expect(order.total_cents).to eq(1100)

      # Update with different items
      result = PlannedOrderService.upsert(
        customer: customer,
        bake_day: bake_day,
        items: [
          { product_variant_id: product_variant.id, qty: 1 },
          { product_variant_id: product_variant_2.id, qty: 2 }
        ]
      )

      # Should update the same order
      expect(result[:order].id).to eq(order.id)
      expect(result[:order].total_cents).to eq(2150)  # 550 + (2 * 800)
      expect(result[:order].order_items.count).to eq(2)
    end

    it 'allows cancelling a planned order' do
      # Create order
      result = PlannedOrderService.upsert(
        customer: customer,
        bake_day: bake_day,
        items: [{ product_variant_id: product_variant.id, qty: 2 }]
      )

      order = result[:order]

      # Cancel it
      cancel_result = PlannedOrderService.cancel(order: order)

      expect(cancel_result[:success]).to be true
      expect(Order.exists?(order.id)).to be false
    end
  end

  describe 'cut-off enforcement' do
    let(:past_cut_off_bake_day) { create(:bake_day, :cut_off_passed) }

    before do
      create(:wallet, customer: customer, balance_cents: 5000)
    end

    it 'prevents creating new orders after cut-off' do
      result = PlannedOrderService.upsert(
        customer: customer,
        bake_day: past_cut_off_bake_day,
        items: [{ product_variant_id: product_variant.id, qty: 2 }]
      )

      expect(result[:error]).to be_present
      expect(result[:error]).to include('Cut-off')
    end

    it 'prevents cancelling orders after cut-off' do
      # Create order before cut-off passes (using a bake day that can order)
      orderable_bake_day = create(:bake_day, :can_order)
      result = PlannedOrderService.upsert(
        customer: customer,
        bake_day: orderable_bake_day,
        items: [{ product_variant_id: product_variant.id, qty: 2 }]
      )

      order = result[:order]

      # Simulate cut-off passing
      orderable_bake_day.update!(cut_off_at: 1.hour.ago)

      # Try to cancel
      cancel_result = PlannedOrderService.cancel(order: order)

      expect(cancel_result[:error]).to be_present
      expect(cancel_result[:error]).to include('Cut-off')
      expect(Order.exists?(order.id)).to be true
    end
  end

  describe 'low balance alerts' do
    let(:bake_day) { create(:bake_day, :can_order) }

    it 'sends low balance alert when balance falls below threshold after debit' do
      # Create wallet with balance just above order total
      wallet = create(:wallet, customer: customer, balance_cents: 1200, low_balance_threshold_cents: 500)

      # Create order for 1100 cents
      result = PlannedOrderService.upsert(
        customer: customer,
        bake_day: bake_day,
        items: [{ product_variant_id: product_variant.id, qty: 2 }]
      )

      # Process the order
      ProcessPlannedOrdersService.process_order(result[:order])

      # Wallet should now have 100 cents (below 500 threshold)
      wallet.reload
      expect(wallet.balance_cents).to eq(100)
      expect(wallet.low_balance?).to be true

      # Two SMS should be sent: confirmation + low balance alert
      expect(SmsMessage.where(customer: customer).count).to eq(2)
    end
  end

  describe 'CheckInsufficientBalanceJob' do
    let(:bake_day_soon) { create(:bake_day, cut_off_at: 3.hours.from_now, baked_on: Date.current + 1.day) }

    it 'sends warning to customers with insufficient balance before cut-off' do
      # Create wallet with insufficient balance
      create(:wallet, customer: customer, balance_cents: 500)

      # Create planned order
      PlannedOrderService.upsert(
        customer: customer,
        bake_day: bake_day_soon,
        items: [{ product_variant_id: product_variant.id, qty: 2 }]  # 1100 cents needed
      )

      # Run the job
      CheckInsufficientBalanceJob.perform_now

      # Should have sent a warning SMS
      expect(SmsMessage.where(customer: customer, kind: :other).count).to eq(1)
    end

    it 'does not send warning if balance is sufficient' do
      # Create wallet with sufficient balance
      create(:wallet, customer: customer, balance_cents: 5000)

      # Create planned order
      PlannedOrderService.upsert(
        customer: customer,
        bake_day: bake_day_soon,
        items: [{ product_variant_id: product_variant.id, qty: 2 }]
      )

      # Run the job
      CheckInsufficientBalanceJob.perform_now

      # Should not have sent any SMS
      expect(SmsMessage.where(customer: customer).count).to eq(0)
    end
  end

  describe 'ProcessPlannedOrdersJob' do
    let(:bake_day_past_cut_off) { create(:bake_day, cut_off_at: 30.minutes.ago, baked_on: Date.current + 1.day) }

    before do
      create(:wallet, customer: customer, balance_cents: 5000)
    end

    it 'processes orders for bake days with recently passed cut-offs' do
      # Create planned order
      order = Order.create!(
        customer: customer,
        bake_day: bake_day_past_cut_off,
        status: :planned,
        source: :calendar,
        total_cents: 1100
      )
      order.order_items.create!(
        product_variant: product_variant,
        qty: 2,
        unit_price_cents: 550
      )

      # Run the job
      ProcessPlannedOrdersJob.perform_now

      # Order should now be paid
      order.reload
      expect(order.paid?).to be true
    end

    it 'ignores bake days with future cut-offs' do
      future_bake_day = create(:bake_day, cut_off_at: 2.days.from_now, baked_on: Date.current + 4.days)

      # Create planned order for future bake day
      order = Order.create!(
        customer: customer,
        bake_day: future_bake_day,
        status: :planned,
        source: :calendar,
        total_cents: 1100
      )

      # Run the job
      ProcessPlannedOrdersJob.perform_now

      # Order should still be planned
      order.reload
      expect(order.planned?).to be true
    end
  end
end
