# frozen_string_literal: true

module Admin
  module Settings
    class FloursController < Admin::BaseController
      before_action :set_flour, only: [:edit, :update, :destroy]

      def index
        @flours = Flour.not_deleted.ordered
      end

      def new
        @flour = Flour.new
      end

      def create
        @flour = Flour.new(flour_params)

        if @flour.save
          redirect_to admin_settings_flours_path, notice: "Farine créée avec succès"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @flour.update(flour_params)
          redirect_to admin_settings_flours_path, notice: "Farine mise à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @flour.product_flours.exists?
          redirect_to admin_settings_flours_path, alert: "Impossible de supprimer une farine utilisée par des produits"
        else
          @flour.soft_delete!
          redirect_to admin_settings_flours_path, notice: "Farine supprimée"
        end
      end

      private

      def set_flour
        @flour = Flour.find(params[:id])
      end

      def flour_params
        params.require(:flour).permit(:name, :position, :kneader_limit_grams)
      end
    end
  end
end
