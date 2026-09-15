# Cycle de vie des RÉSERVATIONS validées en attente de paiement (#pizza-parties).
#
# Trois gestes, tous calés sur le cut-off de la fournée :
#   - à cut-off − 48 h : on sollicite le client (« confirme ton nombre et règle ») ;
#   - à cut-off − 24 h : on relance, une seule fois ;
#   - au cut-off : l'échéance tombe.
#
# À l'échéance, le job N'ANNULE PAS à l'aveugle : il interroge le PaymentIntent
# d'abord. Un paiement Bancontact peut rester `processing` des heures — annuler
# sans regarder rendrait le créneau d'une party en train d'être payée.
class PartyPaymentLifecycleJob < ApplicationJob
  queue_as :default

  REMINDER_BEFORE_CUT_OFF = 24.hours

  # Statuts Stripe d'un paiement qui n'aboutira pas.
  ABANDONED_PI_STATUSES = ExpireStalePendingOrdersJob::ABANDONED_PI_STATUSES

  def perform
    prompt_due
    remind_due
    expire_due
  end

  private

  def awaiting
    Order.awaiting_payment.where(source: :party).includes(:party_event, :party_request)
  end

  def prompt_due(now = Time.current)
    awaiting.where(payment_prompted_at: nil).find_each do |order|
      prompt_at = PartyRequest.payment_prompt_at(order.party_event&.held_on)
      next if prompt_at.nil? || now < prompt_at

      PartyRequestNotifier.payment_prompt(order)
      Rails.logger.info("PartyPaymentLifecycle: sollicitation envoyée pour la commande #{order.id}")
    end
  end

  def remind_due(now = Time.current)
    awaiting.where(payment_reminded_at: nil).find_each do |order|
      due = order.payment_due_at
      next if due.nil? || now < due - REMINDER_BEFORE_CUT_OFF || now >= due

      PartyRequestNotifier.payment_reminder(order)
      Rails.logger.info("PartyPaymentLifecycle: relance de paiement pour la commande #{order.id}")
    end
  end

  def expire_due(now = Time.current)
    awaiting.where.not(payment_due_at: nil).where(payment_due_at: ..now).find_each do |order|
      settle(order)
    end
  end

  # L'état réel du PaymentIntent tranche, pas l'horloge.
  def settle(order)
    intent = order.payment_intent_id.present? ? Stripe::PaymentIntent.retrieve(order.payment_intent_id) : nil

    if intent&.status == "succeeded"
      OrderPaymentFinalizer.call(order: order, payment_intent_id: order.payment_intent_id)
      Rails.logger.info("PartyPaymentLifecycle: commande #{order.id} encaissée à l'échéance (webhook manqué)")
      return
    end

    if intent && !ABANDONED_PI_STATUSES.include?(intent.status)
      # `processing` : le paiement est en vol, on laisse le prochain passage trancher.
      Rails.logger.info("PartyPaymentLifecycle: commande #{order.id} laissée (PI #{intent.status})")
      return
    end

    PartyReservationRelease.new(order).call(cancel_payment_intent: intent.present?)
    PartyRequestNotifier.payment_expired(order)
    Rails.logger.info("PartyPaymentLifecycle: réservation #{order.id} expirée, créneau rendu")
  rescue Stripe::StripeError => e
    Rails.logger.error("PartyPaymentLifecycle: Stripe illisible pour la commande #{order.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
