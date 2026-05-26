# frozen_string_literal: true

module Api
  module V1
    class OrderItemSerializer < BaseSerializer
      def as_json
        line_total = object.qty * object.unit_price_cents
        {
          id: object.id,
          product_variant_id: object.product_variant_id,
          qty: object.qty,
          unit_price_cents: object.unit_price_cents,
          unit_price_euros: euros(object.unit_price_cents),
          line_total_cents: line_total,
          line_total_euros: euros(line_total),
          _links: { product_variant: path("product_variants", object.product_variant_id) }
        }
      end
    end
  end
end
