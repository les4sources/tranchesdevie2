# frozen_string_literal: true

module Admin
  module Settings
    class MoldTypesController < Admin::BaseController
      before_action :set_mold_type, only: [:edit, :update, :destroy]

      def index
        @mold_types = MoldType.not_deleted.ordered
      end

      def new
        @mold_type = MoldType.new
      end

      def create
        @mold_type = MoldType.new(mold_type_params)

        if @mold_type.save
          redirect_to admin_settings_mold_types_path, notice: "Type de moule créé avec succès"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @mold_type.update(mold_type_params)
          redirect_to admin_settings_mold_types_path, notice: "Type de moule mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @mold_type.product_variants.exists?
          redirect_to admin_settings_mold_types_path, alert: "Impossible de supprimer un type de moule utilisé par des variantes"
        else
          @mold_type.soft_delete!
          redirect_to admin_settings_mold_types_path, notice: "Type de moule supprimé"
        end
      end

      private

      def set_mold_type
        @mold_type = MoldType.find(params[:id])
      end

      def mold_type_params
        params.require(:mold_type).permit(:name, :limit, :position)
      end
    end
  end
end
