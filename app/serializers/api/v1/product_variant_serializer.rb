# frozen_string_literal: true

module Api
  module V1
    class ProductVariantSerializer < BaseSerializer
      def as_json
        data = {
          id: object.id,
          product_id: object.product_id,
          name: object.name,
          price_cents: object.price_cents,
          price_euros: euros(object.price_cents),
          active: object.active,
          channel: object.channel,
          flour_quantity: object.flour_quantity,
          restricted: object.restricted?,
          mold_type: mold_type_hash,
          image_url: blob_url(object.product_images.first&.image),
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("product_variants", object.id),
            product: path("products", object.product_id)
          }
        }

        if detail?
          data[:ingredients] = object.variant_ingredients.includes(:ingredient).map do |vi|
            { ingredient_id: vi.ingredient_id, name: vi.ingredient.name, quantity: vi.quantity.to_f, unit: vi.unit_label }
          end
          data[:restricted_group_ids] = object.restricted_group_ids
          data[:availabilities] = object.product_availabilities.map do |a|
            { start_on: a.start_on, end_on: a.end_on }
          end
        end

        data
      end

      private

      def mold_type_hash
        return nil unless object.mold_type

        { id: object.mold_type.id, name: object.mold_type.name, limit: object.mold_type.limit }
      end
    end
  end
end
