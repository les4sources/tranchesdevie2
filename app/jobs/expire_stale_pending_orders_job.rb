# Libère la capacité réservée par des paiements en ligne abandonnés.
#
# Une commande en ligne est créée en statut `pending` AU MOMENT du paiement
# (réservation de capacité). Si le client ne va pas au bout, elle resterait
# `pending` et bloquerait la capacité. Ce job, après un délai de grâce, vérifie
# l'état réel du PaymentIntent côté Stripe :
#   - payé entre-temps (webhook manqué) → on encaisse (idempotent) ;
#   - abandonné/échoué → on annule le PaymentIntent et on supprime la commande
#     (ce qui rend la capacité) ;
#   - encore en cours (`processing`) → on laisse pour le prochain passage.
class ExpireStalePendingOrdersJob < ApplicationJob
  queue_as :default

  GRACE_PERIOD = 15.minutes

  # Statuts Stripe considérés comme non aboutis (la commande peut être supprimée).
  ABANDONED_PI_STATUSES = %w[requires_payment_method requires_confirmation requires_action canceled].freeze

  def perform
    Order.pending
         .where.not(payment_intent_id: nil)
         .where("created_at < ?", GRACE_PERIOD.ago)
         .find_each { |order| process(order) }
  end

  private

  def process(order)
    payment_intent = Stripe::PaymentIntent.retrieve(order.payment_intent_id)

    if payment_intent.status == "succeeded"
      # Le paiement a abouti mais le webhook/page success ne l'a pas encaissé.
      OrderPaymentFinalizer.call(order: order, payment_intent_id: order.payment_intent_id)
      Rails.logger.info("ExpireStalePendingOrders: commande #{order.id} encaissée (PI déjà succeeded)")
    elsif ABANDONED_PI_STATUSES.include?(payment_intent.status)
      cancel_payment_intent(order.payment_intent_id)
      order.destroy
      Rails.logger.info("ExpireStalePendingOrders: commande #{order.id} supprimée (PI #{payment_intent.status}), capacité libérée")
    else
      # ex. "processing" (Bancontact/virement en cours) → on attend.
      Rails.logger.info("ExpireStalePendingOrders: commande #{order.id} laissée (PI #{payment_intent.status})")
    end
  rescue Stripe::StripeError => e
    Rails.logger.error("ExpireStalePendingOrders: erreur Stripe pour commande #{order.id} (PI #{order.payment_intent_id}): #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def cancel_payment_intent(payment_intent_id)
    Stripe::PaymentIntent.cancel(payment_intent_id)
  rescue Stripe::StripeError => e
    # Certains statuts ne sont pas annulables : on ignore, la suppression suffit.
    Rails.logger.warn("ExpireStalePendingOrders: annulation PI #{payment_intent_id} impossible: #{e.message}")
  end
end
