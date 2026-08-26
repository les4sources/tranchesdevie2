# frozen_string_literal: true

module Api
  module V1
    class MoldTypesController < BaseController
      def index
        render_collection(MoldType.not_deleted.ordered, MoldTypeSerializer)
      end

      def show
        render_resource(MoldType.not_deleted.find(params[:id]), MoldTypeSerializer)
      end
    end
  end
end
