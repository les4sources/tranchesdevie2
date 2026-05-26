# frozen_string_literal: true

module Api
  module V1
    class WalletsController < BaseController
      def index
        render_collection(Wallet.includes(:customer).order(:id), WalletSerializer)
      end

      def show
        wallet =
          if params[:customer_id]
            Wallet.find_by!(customer_id: params[:customer_id])
          else
            Wallet.find(params[:id])
          end
        render_resource(wallet, WalletSerializer)
      end
    end
  end
end
