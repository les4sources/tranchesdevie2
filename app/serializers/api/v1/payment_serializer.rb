# frozen_string_literal: true

module Api
  module V1
    class PaymentSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          order_id: object.order_id,
          stripe_payment_intent_id: object.stripe_payment_intent_id,
          status: object.status,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("payments", object.id),
            order: path("orders", object.order_id)
          }
        }
      end
    end
  end
end
