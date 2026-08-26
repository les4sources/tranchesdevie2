# frozen_string_literal: true

module Api
  module V1
    class EmailMessagesController < BaseController
      def index
        scope = EmailMessage.recent
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id]
        scope = scope.where(order_id: params[:order_id]) if params[:order_id]
        scope = scope.where(direction: params[:direction]) if params[:direction].present? && EmailMessage.directions.key?(params[:direction])
        scope = scope.where(kind: params[:kind]) if params[:kind].present? && EmailMessage.kinds.key?(params[:kind])
        render_collection(scope, EmailMessageSerializer)
      end

      def show
        render_resource(EmailMessage.find(params[:id]), EmailMessageSerializer)
      end
    end
  end
end
