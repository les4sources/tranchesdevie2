# frozen_string_literal: true

module Api
  module V1
    class PickupLocationSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          name: object.name,
          description: object.description,
          default: object.default?,
          position: object.position,
          deleted: object.deleted_at.present?,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("pickup_locations", object.id) }
        }
      end
    end
  end
end
