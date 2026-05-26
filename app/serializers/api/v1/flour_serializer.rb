# frozen_string_literal: true

module Api
  module V1
    class FlourSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          name: object.name,
          position: object.position,
          kneader_limit_grams: object.kneader_limit_grams,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("flours", object.id) }
        }
      end
    end
  end
end
