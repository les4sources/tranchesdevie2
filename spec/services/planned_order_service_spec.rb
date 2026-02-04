require 'rails_helper'

RSpec.describe PlannedOrderService do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:product_variant) { create(:product_variant, price_cents: 550) }
  let(:items) do
    [
      { product_variant_id: product_variant.id, qty: 2 }
    ]
  end

  describe '.upsert' do
    context 'creating a new planned order' do
      it 'creates an order with status planned' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        expect(result[:order]).to be_persisted
        expect(result[:order].planned?).to be true
      end

      it 'sets the source to calendar' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        expect(result[:order].calendar?).to be true
      end

      it 'creates order items from the items array' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        expect(result[:order].order_items.count).to eq(1)
        expect(result[:order].order_items.first.qty).to eq(2)
        expect(result[:order].order_items.first.product_variant).to eq(product_variant)
      end

      it 'calculates the total_cents correctly' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        # 2 items * 550 cents = 1100 cents
        expect(result[:order].total_cents).to eq(1100)
      end

      it 'assigns the customer and bake_day' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        expect(result[:order].customer).to eq(customer)
        expect(result[:order].bake_day).to eq(bake_day)
      end
    end

    context 'updating an existing planned order' do
      let!(:existing_order) do
        create(:order, :planned, customer: customer, bake_day: bake_day, source: :calendar)
      end

      it 'updates the existing order instead of creating a new one' do
        expect {
          PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)
        }.not_to change(Order, :count)
      end

      it 'replaces the order items' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        expect(result[:order].order_items.count).to eq(1)
        expect(result[:order].order_items.first.product_variant).to eq(product_variant)
      end

      it 'recalculates the total' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        expect(result[:order].total_cents).to eq(1100)
      end
    end

    context 'when cut-off has passed' do
      let(:bake_day) { create(:bake_day, :cut_off_passed) }

      it 'returns an error' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)

        expect(result[:error]).to be_present
        expect(result[:error]).to include('Cut-off')
      end

      it 'does not create an order' do
        expect {
          PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: items)
        }.not_to change(Order, :count)
      end
    end

    context 'with empty items' do
      it 'returns an error' do
        result = PlannedOrderService.upsert(customer: customer, bake_day: bake_day, items: [])

        expect(result[:error]).to be_present
      end
    end
  end

  describe '.cancel' do
    let!(:order) { create(:order, :planned, customer: customer, bake_day: bake_day, source: :calendar) }

    context 'before cut-off' do
      it 'destroys the planned order' do
        expect {
          PlannedOrderService.cancel(order: order)
        }.to change(Order, :count).by(-1)
      end

      it 'returns success' do
        result = PlannedOrderService.cancel(order: order)
        expect(result[:success]).to be true
      end
    end

    context 'after cut-off' do
      let(:bake_day) { create(:bake_day, :cut_off_passed) }

      it 'returns an error' do
        result = PlannedOrderService.cancel(order: order)

        expect(result[:error]).to be_present
        expect(result[:error]).to include('Cut-off')
      end

      it 'does not destroy the order' do
        expect {
          PlannedOrderService.cancel(order: order)
        }.not_to change(Order, :count)
      end
    end

    context 'when order is not planned' do
      let!(:order) { create(:order, :paid, customer: customer, bake_day: bake_day) }

      it 'returns an error' do
        result = PlannedOrderService.cancel(order: order)

        expect(result[:error]).to be_present
        expect(result[:error]).to include('planifiée')
      end
    end
  end
end
