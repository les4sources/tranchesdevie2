# frozen_string_literal: true

module Admin
  module Settings
    class DoughRatiosController < Admin::BaseController
      before_action :set_ratio, only: [:edit, :update]

      def index
        @ratios = DoughRatio.ordered
      end

      def edit
      end

      def update
        if @ratio.update(ratio_params)
          redirect_to admin_settings_dough_ratios_path, notice: "Ratio mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_ratio
        @ratio = DoughRatio.find(params[:id])
      end

      def ratio_params
        params.require(:dough_ratio).permit(:value)
      end
    end
  end
end
