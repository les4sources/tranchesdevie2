# frozen_string_literal: true

module Api
  module V1
    class PaymentsController < BaseController
      def index
        scope = Payment.order(created_at: :desc)
        scope = scope.where(order_id: params[:order_id]) if params[:order_id]
        render_collection(scope, PaymentSerializer)
      end

      def show
        render_resource(Payment.find(params[:id]), PaymentSerializer)
      end
    end
  end
end
