# frozen_string_literal: true

module Api
  module V1
    class PartyRequestsController < BaseController
      def index
        scope = PartyRequest.includes(:customer, party_request_items: { product_variant: :product })
                            .order(held_on: :desc, created_at: :desc)
        scope = scope.where(state: params[:state]) if params[:state].present?

        render_collection(scope, PartyRequestSerializer)
      end

      def show
        render_resource(PartyRequest.find(params[:id]), PartyRequestSerializer)
      end
    end
  end
end
