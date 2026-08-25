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

  # Prévient les équipes (boulangers + séjours) qu'une Pizza party PRIVÉE vient
  # d'être réservée (#168). Notification INTERNE : l'opt-out e-mail du client n'a
  # aucune prise dessus, et un client sans e-mail ne l'empêche pas de partir.
  #
  # Idempotent par commande, comme send_confirmation : rejouer le webhook, la
  # page de succès ou le job d'expiration ne produit pas de second e-mail.
  def self.send_party_team_notification(order)
    return false unless order&.private_party?
    return false if EmailMessage.exists?(order_id: order.id, kind: :party_team_notification)

    PartyMailer.new_private_party(order).deliver_later
    true
  rescue StandardError => e
    Rails.logger.error("OrderNotificationService error: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  # Notifie le client que sa commande est prête, sur les DEUX canaux (SMS +
  # email), chacun derrière son propre garde-fou (sms_enabled? / email_enabled?).
  # Point d'entrée unique appelé par MarkOrdersReadyJob et par l'admin.
  def self.send_ready(order)
    SmsService.send_ready(order)
    send_ready_email(order)
    true
  end

  def self.send_ready_email(order)
    return false unless order&.customer&.email_enabled?
    return false if EmailMessage.exists?(order_id: order.id, kind: :ready)

    OrderMailer.ready(order).deliver_later
    true
  rescue StandardError => e
    Rails.logger.error("OrderNotificationService error: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end
end
