# frozen_string_literal: true

module Admin
  module Settings
    # CRUD des lieux de vente (#150). Chaque lieu porte une liste de coûts
    # historisés par période (cf. SalesLocationCostsController). Suppression =
    # soft delete : un lieu retiré disparaît des sélecteurs mais reste lisible
    # sur les fournées passées qui le référencent.
    class SalesLocationsController < Admin::BaseController
      before_action :set_sales_location, only: [ :edit, :update, :destroy ]

      def index
        @sales_locations = SalesLocation.not_deleted.ordered
      end

      def new
        @sales_location = SalesLocation.new(active: true)
      end

      def create
        @sales_location = SalesLocation.new(sales_location_params)

        if @sales_location.save
          redirect_to admin_settings_sales_locations_path, notice: "Lieu de vente créé"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @sales_location.update(sales_location_params)
          redirect_to admin_settings_sales_locations_path, notice: "Lieu de vente mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @sales_location.soft_delete!
        redirect_to admin_settings_sales_locations_path, notice: "Lieu de vente supprimé"
      end

      private

      def set_sales_location
        @sales_location = SalesLocation.not_deleted.find(params[:id])
      end

      def sales_location_params
        params.require(:sales_location).permit(:name, :active, :position)
      end
    end
  end
end
