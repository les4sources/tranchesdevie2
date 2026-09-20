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

  # Informe la COMPTA qu'une Pizza party privée est ENCAISSÉE (#289).
  #
  # Sœur de send_party_team_notification, mais branchée sur l'argent et non sur
  # la réservation : la compta doit ajouter la party sur la facture du séjour, ce
  # qui n'a de sens qu'une fois le paiement reçu. Elle ne part donc ni à la
  # création d'une party saisie en admin, ni à la réservation d'une commande cash
  # non encaissée.
  #
  # Notification INTERNE : l'opt-out e-mail du client n'a aucune prise dessus, et
  # un client sans e-mail ne l'empêche pas de partir. Idempotente par commande.
  def self.send_party_accounting_notification(order)
    return false unless order&.private_party?
    return false if EmailMessage.exists?(order_id: order.id, kind: :party_accounting_notification)

    PartyMailer.private_party_paid_for_accounting(order).deliver_later
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

  # Prévient les équipes qu'une party CONFIRMÉE est annulée (#pizza-parties).
  #
  # Symétrique de `send_party_team_notification` : l'équipe séjours était
  # prévenue de l'arrivée d'un groupe, jamais de sa disparition — elle gardait
  # donc une soirée bloquée pour personne.
  def self.notify_team_of_party_cancellation(order)
    return false unless order&.private_party?

    PartyRequestMailer.team_cancellation(order).deliver_later
    true
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

  # Prévient le client d'un remboursement partiel (#remboursement-partiel) sur
  # les DEUX canaux, chacun derrière son garde-fou. L'e-mail porte le détail des
  # lignes rendues — c'est la trace écrite ; le SMS n'en est que l'alerte.
  def self.send_partial_refund(partial_refund)
    send_partial_refund_email(partial_refund)
    SmsService.send_partial_refund(partial_refund)
    true
  end

  def self.send_partial_refund_email(partial_refund)
    return false unless partial_refund&.order&.customer&.email_enabled?

    OrderMailer.partial_refund(partial_refund).deliver_later
    true
  rescue StandardError => e
    Rails.logger.error("OrderNotificationService error: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  # Prévient les boulangers qu'un client signale un problème sur sa commande
  # (#remboursement-partiel). Notification INTERNE : ni opt-out client, ni
  # adresse client — elle part à l'équipe, qui décidera d'un remboursement.
  def self.notify_team_of_order_issue(order_issue)
    return false if order_issue.nil?

    OrderIssueMailer.reported(order_issue).deliver_later
    true
  rescue StandardError => e
    Rails.logger.error("OrderNotificationService error: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
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
