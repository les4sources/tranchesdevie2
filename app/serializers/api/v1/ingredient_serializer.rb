# frozen_string_literal: true

module Api
  module V1
    class IngredientSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          name: object.name,
          unit_type: object.unit_type,
          unit_label: object.unit_label,
          position: object.position,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("ingredients", object.id) }
        }
      end
    end
  end
end
