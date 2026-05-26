# frozen_string_literal: true

module Api
  module V1
    class ArtisansController < BaseController
      def index
        render_collection(Artisan.order(:name), ArtisanSerializer)
      end

      def show
        render_resource(Artisan.find(params[:id]), ArtisanSerializer)
      end
    end
  end
end
