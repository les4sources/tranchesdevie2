# frozen_string_literal: true

module Api
  module V1
    class SmsMessagesController < BaseController
      def index
        scope = SmsMessage.recent
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id]
        scope = scope.where(direction: params[:direction]) if params[:direction].present? && SmsMessage.directions.key?(params[:direction])
        scope = scope.where(kind: params[:kind]) if params[:kind].present? && SmsMessage.kinds.key?(params[:kind])
        render_collection(scope, SmsMessageSerializer)
      end

      def show
        render_resource(SmsMessage.find(params[:id]), SmsMessageSerializer)
      end
    end
  end
end
