# frozen_string_literal: true

module Api
  module V1
    class ProductsController < BaseController
      def index
        scope = Product.not_deleted.ordered.includes(:product_variants)
        render_collection(scope, ProductSerializer)
      end

      def show
        product = Product.not_deleted.includes(
          :product_images,
          { product_flours: :flour },
          { product_variants: [ :mold_type, :product_images ] }
        ).find(params[:id])
        render_resource(product, ProductSerializer)
      end
    end
  end
end
