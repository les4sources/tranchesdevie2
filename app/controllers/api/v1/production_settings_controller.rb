# frozen_string_literal: true

module Api
  module V1
    class ProductionSettingsController < BaseController
      def show
        render_resource(ProductionSetting.current, ProductionSettingSerializer)
      end
    end
  end
end
