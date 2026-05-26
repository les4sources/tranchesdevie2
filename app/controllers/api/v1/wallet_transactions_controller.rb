# frozen_string_literal: true

module Api
  module V1
    class WalletTransactionsController < BaseController
      def index
        scope = WalletTransaction.order(created_at: :desc)
        scope = scope.where(wallet_id: params[:wallet_id]) if params[:wallet_id]
        render_collection(scope, WalletTransactionSerializer)
      end

      def show
        render_resource(WalletTransaction.find(params[:id]), WalletTransactionSerializer)
      end
    end
  end
end
