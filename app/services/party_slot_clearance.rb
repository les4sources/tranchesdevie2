# Ce qu'un blocage de créneau ferait disparaître (#pizza-parties).
#
# Poser un blocage, ou programmer une party publique, sur une date déjà réservée
# n'est pas un geste de calendrier : c'est annuler la soirée de vrais groupes.
# Ce service sert d'abord à le MONTRER — la liste nominative que le boulanger
# voit avant de confirmer — puis à l'exécuter.
#
# Les réservations non payées sont simplement libérées ; les payées passent par
# `RefundService`, qui rembourse, rend le créneau et prévient client et équipe.
# Les demandes encore EN ATTENTE ne sont pas touchées : personne ne décide à la
# place du boulanger, elles restent dans la file, signalées en conflit.
class PartySlotClearance
  Impacted = Struct.new(:order, :customer, :held_on, :slot, :patons, :paid, keyword_init: true) do
    def paid? = paid
  end

  attr_reader :held_on, :slot

  def initialize(held_on:, slot: nil)
    @held_on = held_on.is_a?(Date) ? held_on : safe_date(held_on)
    @slot = slot.presence
  end

  # Réservations vivantes (validées ou confirmées) sur la date, éventuellement
  # restreintes à un créneau.
  def impacted
    return [] if @held_on.nil?

    orders.map do |order|
      Impacted.new(
        order: order,
        customer: order.customer,
        held_on: order.party_event.held_on,
        slot: order.party_event.slot,
        patons: order.party_paton_count,
        paid: order.paid?
      )
    end
  end

  def any?
    impacted.any?
  end

  # Demandes encore en attente sur cette date : on ne les annule PAS, mais le
  # boulanger doit savoir qu'elles existent avant de fermer la soirée.
  def pending_requests
    return PartyRequest.none if @held_on.nil?

    scope = PartyRequest.state_pending.where(held_on: @held_on)
    @slot ? scope.where(slot: @slot) : scope
  end

  # Annule tout ce qui est impacté. Renvoie le nombre de réservations traitées.
  def clear!(reason:)
    count = 0

    impacted.each do |entry|
      if entry.paid?
        RefundService.new(entry.order, cancelled_by: "bakery").call
      else
        PartyReservationRelease.new(entry.order).call(cancel_payment_intent: true)
        entry.order.update_column(:cancelled_by, "bakery")
        PartyRequestNotifier.cancelled_by_bakery(entry.order, reason)
      end

      count += 1
    end

    count
  end

  private

  def safe_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error, ArgumentError, TypeError
    nil
  end

  def orders
    events = PartyEvent.private_events.not_deleted.where(held_on: @held_on)
    events = events.where(slot: @slot) if @slot

    Order.where(party_event_id: events.select(:id))
         .where(status: [ :awaiting_payment, :paid, :ready ])
         .includes(:customer, :party_event, order_items: { product_variant: :product })
  end
end
