# frozen_string_literal: true

module Admin
  module Settings
    # Coûts historisés d'un lieu de vente (#150), par période de validité.
    # Chaque lieu a une liste de paliers (montant + période `valid_from` /
    # `valid_until` nullable) ; le coût applicable à une date est la période qui
    # la couvre (cf. SalesLocationCost.cost_cents_for). Le montant est saisi en
    # euros et converti vers l'entier stocké.
    class SalesLocationCostsController < Admin::BaseController
      before_action :set_sales_location
      before_action :set_cost, only: [ :edit, :update, :destroy ]

      def index
        @costs = @sales_location.sales_location_costs.ordered
      end

      def new
        @cost = @sales_location.sales_location_costs.new(valid_from: Date.current)
      end

      def create
        @cost = @sales_location.sales_location_costs.new(cost_params)

        if @cost.save
          redirect_to admin_settings_sales_location_sales_location_costs_path(@sales_location),
                      notice: "Coût enregistré"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @cost.update(cost_params)
          redirect_to admin_settings_sales_location_sales_location_costs_path(@sales_location),
                      notice: "Coût mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @cost.destroy
        redirect_to admin_settings_sales_location_sales_location_costs_path(@sales_location),
                    notice: "Palier supprimé"
      end

      private

      def set_sales_location
        @sales_location = SalesLocation.not_deleted.find(params[:sales_location_id])
      end

      def set_cost
        @cost = @sales_location.sales_location_costs.find(params[:id])
      end

      def cost_params
        params.require(:sales_location_cost).permit(:amount_euros, :valid_from, :valid_until)
      end
    end
  end
end
