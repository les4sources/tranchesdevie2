# frozen_string_literal: true

module Api
  module V1
    class BakeDaySerializer < BaseSerializer
      def as_json
        data = {
          id: object.id,
          baked_on: object.baked_on,
          cut_off_at: iso(object.cut_off_at),
          can_order: object.can_order?,
          market_day: object.market_day,
          internal_note: object.internal_note,
          total_breads_count: object.total_breads_count,
          total_sales_euros: object.total_sales_euros,
          oven_capacity_grams: object.oven_capacity_grams,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("bake_days", object.id),
            orders: path("bake_days", object.id, "orders")
          }
        }

        if detail?
          data[:artisans] = object.baking_artisans.map { |a| { id: a.id, name: a.name } }
          data[:pickup_locations] = object.open_pickup_locations.map do |location|
            { id: location.id, name: location.name, description: location.description, default: location.default? }
          end
          data[:capacity] = capacity_hash
        end

        data
      end

      private

      def capacity_hash
        service = BakeCapacityService.new(object)
        usage = service.usage
        {
          fill_percentage: service.fill_percentage,
          fully_booked: service.fully_booked?,
          molds: usage[:molds].map { |e| { mold_type: e[:mold_type].name, used: e[:used], limit: e[:limit] } },
          kneader: usage[:kneader].map { |e| { flour: e[:flour].name, used_grams: e[:used], limit_grams: e[:limit] } },
          oven: { used_grams: usage[:oven][:used], limit_grams: usage[:oven][:limit] }
        }
      end
    end
  end
end
