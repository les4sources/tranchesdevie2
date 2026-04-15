class ProcessPlannedOrdersService
  class << self
    def process_for_bake_day(bake_day)
      # Only notify customers for bake days that have not yet passed.
      # When catching up on stale cut-offs (bake_day already in the past),
      # the bread is long gone so a confirmation/cancellation SMS would
      # be confusing; we still update the order status but stay silent.
      send_sms = bake_day.baked_on >= Date.current
      orders = Order.planned.where(bake_day: bake_day)

      orders.find_each do |order|
        process_order(order, send_sms: send_sms)
      end
    end

    def process_order(order, send_sms: true)
      # Reload customer to ensure fresh wallet association
      wallet = order.customer.reload.wallet

      if wallet.nil? || !wallet.can_cover?(order.total_cents)
        cancel_order(order, send_sms: send_sms)
        return
      end

      Order.transaction do
        WalletService.debit_for_order(wallet: wallet, order: order)
        order.update!(status: :paid)
      end

      SmsService.send_planned_order_confirmed(order) if send_sms

      # Check for low balance alert after debit
      if send_sms && wallet.reload.low_balance?
        SmsService.send_low_balance_alert(order.customer)
      end
    rescue StandardError => e
      Rails.logger.error("Error processing planned order #{order.id}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end

    private

    def cancel_order(order, send_sms: true)
      order.update!(status: :cancelled)
      SmsService.send_planned_order_cancelled(order) if send_sms
    rescue StandardError => e
      Rails.logger.error("Error cancelling planned order #{order.id}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end
  end
end
