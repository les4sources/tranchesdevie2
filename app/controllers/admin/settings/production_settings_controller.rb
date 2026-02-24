# frozen_string_literal: true

module Admin
  module Settings
    class ProductionSettingsController < Admin::BaseController
      def edit
        @production_setting = ProductionSetting.current
      end

      def update
        @production_setting = ProductionSetting.current

        if @production_setting.update(production_setting_params)
          redirect_to admin_settings_path, notice: "Capacités de production mises à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def production_setting_params
        params.require(:production_setting).permit(:oven_capacity_grams, :market_day_oven_capacity_grams)
      end
    end
  end
end
