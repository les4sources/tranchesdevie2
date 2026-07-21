# Libère les réservations de capacité (commandes :pending) qu'un client a déjà
# posées sur une fournée, avant d'en créer une nouvelle au checkout.
#
# Contexte : chaque appel à create_payment_intent crée une commande :pending qui
# réserve la capacité. Si le client retente (rechargement, changement de moyen
# de paiement), sa propre réservation précédente compte dans le contrôle de
# capacité et sa commande est comptée double — « capacité dépassée » à tort.
#
# On applique la même logique prudente qu'ExpireStalePendingOrdersJob, mais
# ciblée sur le client, sans délai de grâce :
#   - PI succeeded → on ne touche pas (le webhook/finalizer va encaisser) ;
#   - PI abandonné/échoué (ou absent) → on annule le PI et on supprime la
#     commande, ce qui rend la capacité ;
#   - PI en cours (processing) → on laisse (paiement Bancontact en vol).
class PendingReservationReleaseService
  def self.call(customer:, bake_day:)
    new(customer: customer, bake_day: bake_day).call
  end

  def initialize(customer:, bake_day:)
    @customer = customer
    @bake_day = bake_day
  end

  def call
    return unless @customer && @bake_day

    Order.pending
         .where(customer: @customer, bake_day: @bake_day, source: :checkout)
         .find_each { |order| release(order) }
  end

  private

  def release(order)
    if order.payment_intent_id.blank?
      # PI jamais créé (crash entre create! et update!) : réservation orpheline.
      order.destroy
      return
    end

    payment_intent = Stripe::PaymentIntent.retrieve(order.payment_intent_id)

    if ExpireStalePendingOrdersJob::ABANDONED_PI_STATUSES.include?(payment_intent.status)
      cancel_payment_intent(order.payment_intent_id)
      order.destroy
      Rails.logger.info("PendingReservationRelease: commande #{order.id} supprimée (PI #{payment_intent.status}), capacité libérée")
    else
      # succeeded (webhook en route) ou processing (Bancontact en vol) : on laisse.
      Rails.logger.info("PendingReservationRelease: commande #{order.id} laissée (PI #{payment_intent.status})")
    end
  rescue Stripe::StripeError => e
    # Un pépin Stripe ne doit pas bloquer le checkout en cours : on laisse la
    # réservation, le job d'expiration la rattrapera.
    Rails.logger.error("PendingReservationRelease: erreur Stripe pour commande #{order.id} (PI #{order.payment_intent_id}): #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def cancel_payment_intent(payment_intent_id)
    Stripe::PaymentIntent.cancel(payment_intent_id)
  rescue Stripe::StripeError => e
    # Certains statuts ne sont pas annulables : la suppression suffit.
    Rails.logger.warn("PendingReservationRelease: annulation PI #{payment_intent_id} impossible: #{e.message}")
  end
end
