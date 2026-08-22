# frozen_string_literal: true

module Api
  module V1
    class ProductSerializer < BaseSerializer
      def as_json
        data = {
          id: object.id,
          name: object.name,
          short_name: object.short_name,
          description: object.description,
          category: object.category,
          channel: object.channel,
          active: object.active,
          position: object.position,
          flour_quantity: object.flour_quantity,
          flour_composition: object.flour_composition_label,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("products", object.id),
            variants: path("products", object.id, "variants")
          }
        }

        if detail?
          data[:variants] = ProductVariantSerializer.many(object.product_variants, context)
          data[:images] = object.product_images.ordered.map do |img|
            { id: img.id, position: img.position, url: blob_url(img.image) }
          end
          data[:flours] = object.product_flours.includes(:flour).map do |pf|
            { flour_id: pf.flour_id, name: pf.flour.name, percentage: pf.percentage }
          end
        end

        data
      end
    end
  end
end
