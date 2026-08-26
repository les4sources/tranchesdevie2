# frozen_string_literal: true

module Api
  module V1
    class GroupSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          name: object.name,
          discount_percent: object.discount_percent,
          customers_count: object.customers.count,
          discounts: object.group_product_discounts.map do |d|
            {
              id: d.id,
              product_id: d.product_id,
              product_variant_id: d.product_variant_id,
              discount_kind: d.discount_kind,
              discount_value: d.discount_value,
              discount_value_euros: d.discount_kind == "fixed" ? euros(d.discount_value) : nil
            }
          end,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("groups", object.id) }
        }
      end
    end
  end
end
