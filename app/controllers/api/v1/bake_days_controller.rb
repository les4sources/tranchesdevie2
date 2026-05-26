# frozen_string_literal: true

module Api
  module V1
    class BakeDaysController < BaseController
      def index
        render_collection(BakeDay.ordered.includes(:baking_artisans), BakeDaySerializer)
      end

      def show
        bake_day = BakeDay.includes(:baking_artisans).find(params[:id])
        render_resource(bake_day, BakeDaySerializer)
      end
    end
  end
end
