class ProcessPlannedOrdersService
  class << self
    def process_for_bake_day(bake_day)
      orders = Order.planned.where(bake_day: bake_day)

      orders.find_each do |order|
        process_order(order)
      end
    end

    def process_order(order)
      # Reload customer to ensure fresh wallet association
      wallet = order.customer.reload.wallet

      if wallet.nil? || !wallet.can_cover?(order.total_cents)
        cancel_order(order)
        return
      end

      Order.transaction do
        WalletService.debit_for_order(wallet: wallet, order: order)
        order.update!(status: :paid)
      end

      SmsService.send_planned_order_confirmed(order)

      # Check for low balance alert after debit
      if wallet.reload.low_balance?
        SmsService.send_low_balance_alert(order.customer)
      end
    rescue StandardError => e
      Rails.logger.error("Error processing planned order #{order.id}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end

    private

    def cancel_order(order)
      order.update!(status: :cancelled)
      SmsService.send_planned_order_cancelled(order)
    rescue StandardError => e
      Rails.logger.error("Error cancelling planned order #{order.id}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end
  end
end
