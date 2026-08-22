# frozen_string_literal: true

module Api
  module V1
    class OrdersController < BaseController
      def index
        scope = Order.recent.includes(:order_items, :payment, :wallet_transactions)
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id]
        scope = scope.where(bake_day_id: params[:bake_day_id]) if params[:bake_day_id]
        scope = scope.where(status: params[:status]) if params[:status].present? && Order.statuses.key?(params[:status])
        scope = scope.where(source: params[:source]) if params[:source].present? && Order.sources.key?(params[:source])
        render_collection(scope, OrderSerializer)
      end

      def show
        order = Order.includes(:order_items, :payment, :wallet_transactions).find(params[:id])
        render_resource(order, OrderSerializer)
      end
    end
  end
end
