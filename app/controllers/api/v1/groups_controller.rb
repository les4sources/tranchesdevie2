# frozen_string_literal: true

module Api
  module V1
    class GroupsController < BaseController
      def index
        render_collection(Group.order(:name), GroupSerializer)
      end

      def show
        render_resource(Group.find(params[:id]), GroupSerializer)
      end
    end
  end
end
