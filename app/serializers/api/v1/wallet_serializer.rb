# frozen_string_literal: true

module Api
  module V1
    class WalletSerializer < BaseSerializer
      def as_json
        data = {
          id: object.id,
          customer_id: object.customer_id,
          balance_cents: object.balance_cents,
          balance_euros: object.balance_euros,
          low_balance_threshold_cents: object.low_balance_threshold_cents,
          low_balance: object.low_balance?,
          available_balance_cents: object.available_balance_cents,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("wallets", object.id),
            customer: path("customers", object.customer_id),
            transactions: path("wallets", object.id, "transactions")
          }
        }

        if detail?
          # Cap inline transactions; the full set is paginated at /wallets/:id/transactions.
          data[:transactions] = WalletTransactionSerializer.many(
            object.wallet_transactions.order(created_at: :desc).limit(100), context
          )
        end

        data
      end
    end
  end
end
