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
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("groups", object.id) }
        }
      end
    end
  end
end
