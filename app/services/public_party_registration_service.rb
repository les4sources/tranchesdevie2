# Inscription CLIENT à une pizza party PUBLIQUE (#pizza-parties) : crée la
# commande party rattachée à l'événement créé par l'admin, après contrôle des
# inscriptions (ouvertes ?) et de la jauge SOUS verrou consultatif par
# événement — deux groupes ne peuvent pas prendre les mêmes dernières places.
#
# Pendant public de PartyReservationService (privé) : ici l'événement EXISTE
# déjà, on n'en crée jamais. Les commandes :pending du même client sur cet
# événement (tentative de paiement abandonnée) sont libérées d'abord.
class PublicPartyRegistrationService
  # pg_advisory_xact_lock(int4, int4) — espace distinct des verrous bake_day,
  # portefeuille (8100) et créneau privé (8300).
  LOCK_NAMESPACE = 8_400

  attr_reader :order, :errors

  def initialize(customer:, party_event:, cart_items:,
                 payment_method: "online", payment_intent_id: nil, group_name: nil)
    @customer = customer
    @party_event = party_event
    @cart_items = cart_items
    @payment_method = payment_method
    @payment_intent_id = payment_intent_id
    @group_name = group_name
    @errors = []
  end

  def call
    @errors = []

    unless @party_event&.kind_public_party?
      @errors << "Événement introuvable"
      return false
    end

    release_stale_pending_registrations

    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{@party_event.id})"
      )

      unless @party_event.registration_open?
        @errors << "Les inscriptions pour cet événement sont clôturées"
        raise ActiveRecord::Rollback
      end

      remaining = @party_event.seats_remaining
      if remaining && requested_seats > remaining
        @errors << if remaining.zero?
          "Cet événement est complet"
        else
          "Il ne reste que #{remaining} place#{"s" if remaining > 1} pour cet événement"
        end
        raise ActiveRecord::Rollback
      end

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
      @order = nil
      false
    else
      @order
    end
  end

  private

  def requested_seats
    @cart_items.sum { |item| item["qty"].to_i }
  end

  # Même prudence que PartyReservationService : PI abouti ou en vol → on laisse.
  def release_stale_pending_registrations
    return unless @customer&.persisted?

    Order.pending
         .where(customer: @customer, source: :party, party_event: @party_event)
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
        Rails.logger.warn("PublicPartyRegistration: annulation PI #{stale.payment_intent_id} impossible: #{e.message}")
      end
      stale.destroy
      Rails.logger.info("PublicPartyRegistration: inscription pending #{stale.id} libérée")
    end
  rescue Stripe::StripeError => e
    Rails.logger.error("PublicPartyRegistration: erreur Stripe commande #{stale.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
