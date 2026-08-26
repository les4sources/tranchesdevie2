# frozen_string_literal: true

module Api
  module V1
    class ProductVariantsController < BaseController
      def index
        scope = ProductVariant.includes(:mold_type, :product_images)
        scope = scope.where(product_id: params[:product_id]) if params[:product_id]
        render_collection(scope.order(:product_id, :id), ProductVariantSerializer)
      end

      def show
        variant = ProductVariant.includes(
          :mold_type, :product_images, :product_availabilities, { variant_ingredients: :ingredient }
        ).find(params[:id])
        render_resource(variant, ProductVariantSerializer)
      end
    end
  end
end
