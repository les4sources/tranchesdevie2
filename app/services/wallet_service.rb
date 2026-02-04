class WalletService
  class << self
    def top_up(wallet:, amount_cents:, stripe_payment_intent_id:)
      wallet.credit!(
        amount_cents,
        type: :top_up,
        stripe_payment_intent_id: stripe_payment_intent_id,
        description: "Recharge de #{amount_cents / 100.0}€"
      )
    end

    def debit_for_order(wallet:, order:)
      wallet.debit!(
        order.total_cents,
        type: :order_debit,
        order: order,
        description: "Commande #{order.order_number}"
      )
    end

    def refund_for_order(wallet:, order:)
      wallet.credit!(
        order.total_cents,
        type: :order_refund,
        order: order,
        description: "Remboursement commande #{order.order_number}"
      )
    end
  end
end
