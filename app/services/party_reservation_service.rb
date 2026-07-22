# Réservation CLIENT d'une pizza party privée (#pizza-parties) : crée
# l'événement privé (date + créneau choisis dans le calendrier de
# disponibilités) ET sa commande, de façon atomique.
#
# La disponibilité est revalidée SOUS un verrou consultatif par (date, créneau) :
# deux clients ne peuvent pas réserver le même dernier créneau en concurrence
# (même patron que le verrou bake_day d'OrderCreationService, espace distinct).
#
# Avant de réserver, les commandes party :pending du même client (tentative de
# paiement précédente abandonnée) sont libérées — sinon sa propre réservation
# compterait dans la capacité et bloquerait son retry. La destruction de la
# commande libère aussi son événement privé orphelin (callback Order).
class PartyReservationService
  # pg_advisory_xact_lock(int4, int4) — espace distinct des verrous bake_day
  # (mono-argument) et portefeuille (8100).
  LOCK_NAMESPACE = 8_300

  attr_reader :order, :party_event, :errors

  def initialize(customer:, date:, slot:, cart_items:,
                 payment_method: "online", payment_intent_id: nil, group_name: nil)
    @customer = customer
    @date = date.is_a?(Date) ? date : Date.iso8601(date.to_s)
    @slot = slot.to_s
    @cart_items = cart_items
    @payment_method = payment_method
    @payment_intent_id = payment_intent_id
    @group_name = group_name
    @errors = []
  rescue Date::Error, ArgumentError, TypeError
    @date = nil
    @errors = []
  end

  def call
    @errors = []

    unless @date && PartyEvent.slots.key?(@slot)
      @errors << "Date ou créneau de la Pizza party invalide"
      return false
    end

    release_stale_pending_reservations

    ActiveRecord::Base.transaction do
      lock_slot!

      unless PartyEvent.private_slot_available?(@date, @slot)
        @errors << "Ce créneau n'est plus disponible. Choisis une autre date."
        raise ActiveRecord::Rollback
      end

      @party_event = PartyEvent.create!(kind: :private_party, held_on: @date, slot: @slot)

      service = PartyOrderCreationService.new(
        customer: @customer,
        party_event: @party_event,
        cart_items: @cart_items,
        payment_intent_id: @payment_intent_id,
        payment_method: @payment_method,
        group_name: @group_name
      )
      @order = service.call

      unless @order
        @errors.concat(service.errors)
        raise ActiveRecord::Rollback
      end
    end

    if @errors.any?
      @order = @party_event = nil
      false
    else
      @order
    end
  end

  private

  # Sérialise les réservations concurrentes sur le même (date, créneau).
  # Clé int4 : jour julien × 2 + index du créneau.
  def lock_slot!
    key = @date.jd * 2 + PartyEvent.slots[@slot]
    ActiveRecord::Base.connection.execute(
      "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{key})"
    )
  end

  # Libère les réservations party :pending du client (mêmes règles prudentes que
  # PendingReservationReleaseService : PI abouti ou en vol → on ne touche pas).
  def release_stale_pending_reservations
    return unless @customer&.persisted?

    Order.pending
         .where(customer: @customer, source: :party)
         .find_each { |stale| release(stale) }
  end

  def release(stale)
    if stale.payment_intent_id.blank?
      stale.destroy
      return
    end

    payment_intent = Stripe::PaymentIntent.retrieve(stale.payment_intent_id)

    if ExpireStalePendingOrdersJob::ABANDONED_PI_STATUSES.include?(payment_intent.status)
      begin
        Stripe::PaymentIntent.cancel(stale.payment_intent_id)
      rescue Stripe::StripeError => e
        Rails.logger.warn("PartyReservation: annulation PI #{stale.payment_intent_id} impossible: #{e.message}")
      end
      stale.destroy
      Rails.logger.info("PartyReservation: réservation pending #{stale.id} libérée")
    end
  rescue Stripe::StripeError => e
    # Un pépin Stripe ne bloque pas la réservation en cours ; le job d'expiration rattrapera.
    Rails.logger.error("PartyReservation: erreur Stripe commande #{stale.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
