# frozen_string_literal: true

module Api
  module V1
    class MoldTypeSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          name: object.name,
          limit: object.limit,
          position: object.position,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("mold_types", object.id) }
        }
      end
    end
  end
end
