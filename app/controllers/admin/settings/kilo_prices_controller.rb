# frozen_string_literal: true

module Admin
  module Settings
    # Historique des prix au kilo (#209), commun aux ingrédients et aux farines.
    #
    # Le principe est le même que `VariantCostPrice` : on n'écrase jamais un
    # prix, on ajoute un palier avec sa date d'effet. C'est ce qui garantit
    # qu'« un reporting passé ne change jamais ».
    #
    # Un palier reste corrigeable et supprimable — une faute de frappe doit
    # pouvoir se réparer — mais c'est alors une correction assumée, pas le geste
    # normal de changer de prix.
    class KiloPricesController < Admin::BaseController
      before_action :set_owner
      before_action :set_price, only: [ :edit, :update, :destroy ]

      def index
        @prices = @owner.kilo_prices.ordered
      end

      def new
        @price = build_price(active_from: Date.current)
      end

      def create
        @price = build_price(price_params)

        if @price.save
          redirect_to owner_prices_path, notice: "Prix enregistré."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @price.update(price_params)
          redirect_to owner_prices_path, notice: "Prix corrigé."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @price.destroy!

        redirect_to owner_prices_path, notice: "Prix supprimé."
      end

      private

      # Le contrôleur sert deux parents ; on les départage sur les paramètres de
      # route plutôt que de dupliquer un contrôleur par modèle.
      def set_owner
        @owner =
          if params[:ingredient_id].present?
            Ingredient.not_deleted.find(params[:ingredient_id])
          else
            Flour.not_deleted.find(params[:flour_id])
          end
      end

      def ingredient? = @owner.is_a?(Ingredient)

      def build_price(attributes)
        ingredient? ? @owner.ingredient_prices.new(attributes) : @owner.flour_prices.new(attributes)
      end

      def set_price
        @price = @owner.kilo_prices.find(params[:id])
      end

      def owner_prices_path
        if ingredient?
          admin_settings_ingredient_kilo_prices_path(@owner)
        else
          admin_settings_flour_kilo_prices_path(@owner)
        end
      end
      helper_method :owner_prices_path

      def price_params
        params.require(:kilo_price).permit(:amount_euros, :active_from)
      end
    end
  end
end
