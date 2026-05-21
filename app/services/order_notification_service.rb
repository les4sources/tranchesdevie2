# Sends the order confirmation email once an order is paid.
#
# Idempotent: safe to call from every path that confirms an order (Stripe
# webhook, checkout success page, cash order). Skips customers without an email
# or who opted out of non-OTP emails.
class OrderNotificationService
  def self.send_confirmation(order)
    return false unless order&.customer&.email_enabled?
    return false if EmailMessage.exists?(order_id: order.id, kind: :confirmation)

    OrderMailer.confirmation(order).deliver_later
    true
  rescue StandardError => e
    Rails.logger.error("OrderNotificationService error: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end
end
