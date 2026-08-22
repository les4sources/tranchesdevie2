# frozen_string_literal: true

module Api
  module V1
    class WalletTransactionSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          wallet_id: object.wallet_id,
          order_id: object.order_id,
          transaction_type: object.transaction_type,
          amount_cents: object.amount_cents,
          amount_euros: object.amount_euros,
          description: object.description,
          stripe_payment_intent_id: object.stripe_payment_intent_id,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("wallet_transactions", object.id),
            wallet: path("wallets", object.wallet_id)
          }
        }
      end
    end
  end
end
