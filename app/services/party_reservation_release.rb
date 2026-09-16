# Libère une réservation de Pizza party privée qui n'ira pas à son terme
# (#pizza-parties) : échéance de paiement dépassée, validation retirée par la
# boulangerie, créneau bloqué après coup.
#
# « Rendre le créneau » n'est PAS annuler la commande : la capacité compte les
# `PartyEvent` non supprimés, pas les commandes. Sans le soft-delete de
# l'événement, un vendredi soir resterait occupé pour toujours par une party que
# personne n'a payée.
class PartyReservationRelease
  def initialize(order)
    @order = order
  end

  def call(cancel_payment_intent: false)
    return false if @order.nil? || @order.cancelled?

    cancel_intent! if cancel_payment_intent && @order.payment_intent_id.present?

    ActiveRecord::Base.transaction do
      @order.transition_to!(:cancelled) if @order.can_transition_to?(:cancelled)
      release_event
    end

    true
  end

  private

  def release_event
    event = @order.party_event
    return unless event&.kind_private_party?

    # Le post-it claudy ne part que si la party avait été confirmée : une
    # réservation non payée n'en a jamais eu (ISC-32).
    OrderNotificationService.remove_party_calendar_note(@order) if @order.claudy_note_id.present?

    return if event.orders.where.not(id: @order.id).where.not(status: Order.statuses[:cancelled]).exists?

    event.soft_delete!
  end

  def cancel_intent!
    Stripe::PaymentIntent.cancel(@order.payment_intent_id)
  rescue Stripe::StripeError => e
    # Un PaymentIntent déjà abouti ou déjà annulé ne doit pas empêcher de rendre
    # le créneau : le job d'échéance revérifie le statut réel avant d'annuler.
    Rails.logger.warn("PartyReservationRelease: annulation PI #{@order.payment_intent_id} impossible: #{e.message}")
  end
end
