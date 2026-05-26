# frozen_string_literal: true

module Api
  module V1
    class FloursController < BaseController
      def index
        render_collection(Flour.not_deleted.ordered, FlourSerializer)
      end

      def show
        render_resource(Flour.not_deleted.find(params[:id]), FlourSerializer)
      end
    end
  end
end
