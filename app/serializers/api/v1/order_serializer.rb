# frozen_string_literal: true

module Api
  module V1
    class OrderSerializer < BaseSerializer
      def as_json
        data = {
          id: object.id,
          order_number: object.order_number,
          status: object.status,
          source: object.source,
          total_cents: object.total_cents,
          total_euros: object.total_euros,
          requires_invoice: object.requires_invoice,
          payment_method: object.payment_method,
          payment_received: object.payment_received?,
          paid_at: iso(object.paid_at),
          customer_id: object.customer_id,
          bake_day_id: object.bake_day_id,
          items: object.order_items.map { |item| OrderItemSerializer.new(item, context).as_json },
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("orders", object.id),
            customer: path("customers", object.customer_id),
            bake_day: path("bake_days", object.bake_day_id)
          }
        }

        data[:payment] = PaymentSerializer.one(object.payment, context) if detail?
        data
      end
    end
  end
end
