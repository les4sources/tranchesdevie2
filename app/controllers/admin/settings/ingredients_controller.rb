# frozen_string_literal: true

module Admin
  module Settings
    class IngredientsController < Admin::BaseController
      before_action :set_ingredient, only: [:edit, :update, :destroy]

      def index
        @ingredients = Ingredient.not_deleted.ordered
      end

      def new
        @ingredient = Ingredient.new
      end

      def create
        @ingredient = Ingredient.new(ingredient_params)

        if @ingredient.save
          redirect_to admin_settings_ingredients_path, notice: "Ingrédient créé avec succès"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @ingredient.update(ingredient_params)
          redirect_to admin_settings_ingredients_path, notice: "Ingrédient mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @ingredient.variant_ingredients.exists?
          redirect_to admin_settings_ingredients_path, alert: "Impossible de supprimer un ingrédient utilisé par des variantes"
        else
          @ingredient.soft_delete!
          redirect_to admin_settings_ingredients_path, notice: "Ingrédient supprimé"
        end
      end

      private

      def set_ingredient
        @ingredient = Ingredient.find(params[:id])
      end

      def ingredient_params
        params.require(:ingredient).permit(:name, :unit_type, :position)
      end
    end
  end
end
