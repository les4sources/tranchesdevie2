# frozen_string_literal: true

module Api
  module V1
    class ProductionSettingSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          oven_capacity_grams: object.oven_capacity_grams,
          market_day_oven_capacity_grams: object.market_day_oven_capacity_grams,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("production_setting") }
        }
      end
    end
  end
end
