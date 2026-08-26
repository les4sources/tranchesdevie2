# frozen_string_literal: true

module Api
  module V1
    class ArtisanSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          name: object.name,
          active: object.active,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("artisans", object.id) }
        }
      end
    end
  end
end
