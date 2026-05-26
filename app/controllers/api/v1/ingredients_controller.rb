# frozen_string_literal: true

module Api
  module V1
    class IngredientsController < BaseController
      def index
        render_collection(Ingredient.not_deleted.ordered, IngredientSerializer)
      end

      def show
        render_resource(Ingredient.not_deleted.find(params[:id]), IngredientSerializer)
      end
    end
  end
end
