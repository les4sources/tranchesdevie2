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

  # Pose la note « Pizza party » sur le calendrier de claudy — l'application des
  # 4 Sources (#259). Sœur de send_party_team_notification : mêmes gardes (party
  # PRIVÉE uniquement), mêmes points d'appel, pour que le lieu voie venir un
  # groupe au moment exact où l'équipe est prévenue par e-mail.
  #
  # L'appel HTTP part en tâche de fond : claudy indisponible ne doit jamais
  # faire échouer un paiement ni un checkout.
  def self.sync_party_calendar_note(order)
    return false unless order&.private_party?

    SyncClaudyPartyNoteJob.perform_later(order.id, SyncClaudyPartyNoteJob::CREATE)
    true
  rescue StandardError => e
    Rails.logger.error("OrderNotificationService error: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  # Retire la note du calendrier de claudy quand la party privée est annulée et
  # remboursée : un post-it fantôme est pire que pas de post-it du tout.
  def self.remove_party_calendar_note(order)
    return false unless order&.private_party?
    return false if order.claudy_note_id.blank?

    SyncClaudyPartyNoteJob.perform_later(order.id, SyncClaudyPartyNoteJob::DELETE)
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
