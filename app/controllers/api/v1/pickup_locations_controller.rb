# frozen_string_literal: true

module Api
  module V1
    class PickupLocationsController < BaseController
      def index
        render_collection(PickupLocation.not_deleted.ordered, PickupLocationSerializer)
      end

      # Un lieu supprimé (soft delete) reste consultable : des commandes le
      # référencent encore.
      def show
        render_resource(PickupLocation.find(params[:id]), PickupLocationSerializer)
      end
    end
  end
end
