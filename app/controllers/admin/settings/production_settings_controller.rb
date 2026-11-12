# frozen_string_literal: true

module Admin
  module Settings
    class ProductionSettingsController < Admin::BaseController
      before_action :load_bread_variant_options

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

      def load_bread_variant_options
        @bread_variant_options = ProductVariant.joins(:product)
                                               .merge(Product.not_deleted.where(category: :breads))
                                               .includes(:product)
                                               .sort_by { |variant| [ variant.product.name.downcase, variant.name.downcase ] }
                                               .map { |variant| [ "#{variant.product.name} — #{variant.name}", variant.id ] }
      end

      def production_setting_params
        params.require(:production_setting).permit(:oven_capacity_grams, :market_day_oven_capacity_grams, :private_party_slot_capacity,
                                                           :camembert_bread_variant_id)
      end
    end
  end
end
