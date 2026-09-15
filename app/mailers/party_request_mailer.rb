# E-mails du parcours de réservation Pizza party (#pizza-parties).
#
# TOUS TRANSACTIONNELS : ils ignorent `Customer#email_opt_out`, exactement comme
# les e-mails d'OTP. Un client désabonné qui réserve une party doit recevoir son
# lien de paiement — sans quoi sa réservation expire sans qu'il ait jamais été
# prévenu. Le désabonnement porte sur les envois commerciaux, pas sur la
# conversation qu'il a lui-même engagée.
#
# L'e-mail d'équipe (`new_request`) n'a pas de destinataire client : ni
# X-Customer-Id, ni lien de désinscription.
class PartyRequestMailer < ApplicationMailer
  # --- Côté client -----------------------------------------------------------

  def received(party_request)
    @party_request = party_request
    prepare(party_request, :party_request_received)
    mail(to: party_request.customer.email, subject: "Ta demande de Pizza party — #{date_label}")
  end

  def accepted(party_request)
    @party_request = party_request
    @order = party_request.order
    # Deux branches (ISC-26) : avant la sollicitation de J-5, l'e-mail annonce le
    # rendez-vous ; après, il EST la sollicitation — il ne peut pas donner
    # rendez-vous à une date déjà passée.
    prompt_at = party_request.payment_prompt_at
    @prompt_now = prompt_at.nil? || Time.current >= prompt_at
    @prompt_at = prompt_at
    prepare(party_request, :party_request_accepted)
    mail(to: party_request.customer.email, subject: "C'est bon pour ta Pizza party du #{date_label}")
  end

  def refused(party_request)
    @party_request = party_request
    @alternatives = next_available_dates
    prepare(party_request, :party_request_refused)
    mail(to: party_request.customer.email, subject: "Ta demande de Pizza party du #{date_label}")
  end

  def retracted(party_request)
    @party_request = party_request
    @alternatives = next_available_dates
    prepare(party_request, :party_cancelled)
    mail(to: party_request.customer.email, subject: "Ta Pizza party du #{date_label} est annulée")
  end

  def request_expired(party_request)
    @party_request = party_request
    prepare(party_request, :party_request_expired)
    mail(to: party_request.customer.email, subject: "Ta demande de Pizza party du #{date_label} est close")
  end

  # Sollicitation J-5 : confirme ton nombre de participants et paie.
  def payment_prompt(order)
    @order = order
    @party_request = order.party_request
    prepare_order(order, :party_payment_prompt)
    mail(to: order.customer.email, subject: "Pizza party du #{date_label(order)} : confirme et règle ta réservation")
  end

  def payment_reminder(order)
    @order = order
    @party_request = order.party_request
    prepare_order(order, :party_payment_reminder)
    mail(to: order.customer.email, subject: "Rappel — ta Pizza party du #{date_label(order)} n'est pas encore réglée")
  end

  def payment_expired(order)
    @order = order
    prepare_order(order, :party_payment_expired)
    mail(to: order.customer.email, subject: "Ta réservation de Pizza party du #{date_label(order)} a expiré")
  end

  def cancelled_by_bakery(order, reason)
    @order = order
    @reason = reason
    prepare_order(order, :party_cancelled)
    mail(to: order.customer.email, subject: "Ta Pizza party du #{date_label(order)} est annulée")
  end

  def refunded(order)
    @order = order
    prepare_order(order, :party_refunded)
    mail(to: order.customer.email, subject: "Remboursement de ta Pizza party du #{date_label(order)}")
  end

  # --- Côté boulangerie ------------------------------------------------------

  # Prévient boulangers et équipe séjours qu'une party CONFIRMÉE est annulée :
  # la soirée se libère, et personne ne doit rester à attendre un groupe.
  def team_cancellation(order)
    @order = order
    @party_event = order.party_event
    @by_customer = order.cancelled_by == "customer"

    headers["X-Email-Kind"] = "party_cancelled"
    headers["X-Order-Id"] = order.id

    mail(
      to: PartyMailer.notification_to,
      cc: PartyMailer.notification_cc,
      subject: "Pizza party ANNULÉE — #{I18n.l(order.party_event.held_on, format: '%A %-d %B')}"
    )
  end

  # Prévient l'équipe qu'une demande vient d'arriver, avec les deux liens de
  # décision. Les liens sont signés et mènent à une PAGE À BOUTON : aucune action
  # d'état n'est exécutée par le GET, que les clients mail préchargent.
  def new_request(party_request)
    @party_request = party_request
    @accept_url = admin_party_decision_url(token: party_request.signed_id(purpose: :party_decision, expires_in: 30.days), decision: "accept")
    @refuse_url = admin_party_decision_url(token: party_request.signed_id(purpose: :party_decision, expires_in: 30.days), decision: "refuse")

    headers["X-Email-Kind"] = "party_request_team"
    headers["X-Party-Request-Id"] = party_request.id

    mail(
      to: PartyMailer.notification_to,
      cc: PartyMailer.notification_cc,
      subject: "Demande de Pizza party privée — #{date_label}"
    )
  end

  private

  def prepare(party_request, kind)
    headers["X-Email-Kind"] = kind.to_s
    headers["X-Customer-Id"] = party_request.customer_id
    headers["X-Party-Request-Id"] = party_request.id
  end

  def prepare_order(order, kind)
    headers["X-Email-Kind"] = kind.to_s
    headers["X-Customer-Id"] = order.customer_id
    headers["X-Order-Id"] = order.id
    headers["X-Party-Request-Id"] = order.party_request&.id
  end

  def date_label(source = @party_request)
    date = source.respond_to?(:held_on) ? source.held_on : source.party_event.held_on
    I18n.l(date, format: "%A %-d %B")
  end

  # Les prochaines dates encore demandables, pour qu'un refus ne laisse pas le
  # client dans le vide.
  def next_available_dates(limit = 3)
    start = Date.current + PartyRequest::MINIMUM_NOTICE_DAYS
    PartyRequest.requestable_availability(start..(start + 8.weeks))
                .select { |_date, slots| slots.values.any? }
                .keys
                .first(limit)
  end
end
