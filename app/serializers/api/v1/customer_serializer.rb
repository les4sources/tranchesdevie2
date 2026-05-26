# frozen_string_literal: true

module Api
  module V1
    class CustomerSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          first_name: object.first_name,
          last_name: object.last_name,
          full_name: object.full_name,
          phone_e164: object.phone_e164,
          email: object.email,
          billable: object.billable,
          sms_opt_out: object.sms_opt_out,
          email_opt_out: object.email_opt_out,
          effective_discount_percent: object.effective_discount_percent,
          groups: object.groups.map { |g| { id: g.id, name: g.name, discount_percent: g.discount_percent } },
          wallet_balance_cents: object.wallet&.balance_cents,
          wallet_balance_euros: object.wallet && euros(object.wallet.balance_cents),
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("customers", object.id),
            orders: path("customers", object.id, "orders"),
            wallet: path("customers", object.id, "wallet")
          }
        }
      end
    end
  end
end
