# Réponse de la boulangerie à une demande de Pizza party privée (#pizza-parties).
#
# Trois gestes : valider, refuser, retirer une validation non payée.
#
# La VALIDATION est le moment où la réservation prend corps : c'est ici, et pas à
# la demande, qu'on vérifie la disponibilité et la capacité du créneau — deux
# groupes peuvent avoir demandé la même soirée. Le contrôle s'exécute sous le
# verrou consultatif du créneau (même espace que l'ancien PartyReservationService),
# sinon deux boulangers validant en parallèle passeraient tous les deux.
#
# La commande naît en `awaiting_payment` : validée n'est pas vendue. Ce statut est
# hors du CA (COMPLETED_STATUSES) et hors des feuilles de production
# (PRODUCTION_STATUSES) — tant que l'argent n'est pas encaissé, la party ne pèse
# ni sur les chiffres ni sur le pétrin.
class PartyDecisionService
  LOCK_NAMESPACE = 8_300

  attr_reader :party_request, :order, :errors

  def initialize(party_request, decided_by:)
    @party_request = party_request
    @decided_by = decided_by.presence || "boulangerie"
    @errors = []
  end

  # Valide la demande : crée le PartyEvent + l'Order (non payé) et prévient le client.
  def accept
    @errors = []

    ActiveRecord::Base.transaction do
      # Verrouille la LIGNE de la demande : le même clic peut arriver deux fois
      # (lien e-mail rejoué, double soumission, deux boulangers).
      @party_request.lock!

      unless @party_request.state_pending?
        @errors << already_handled_message
        raise ActiveRecord::Rollback
      end

      unless @party_request.decidable?
        @errors << "Cette demande est trop proche de la date pour être validée."
        raise ActiveRecord::Rollback
      end

      # Sans lignes figées, il n'y a pas de prix à facturer : la commande naîtrait
      # à 0 € et exploserait sur sa validation de total. On le dit plutôt que de
      # laisser remonter un RecordInvalid illisible.
      if @party_request.party_request_items.empty?
        @errors << "Cette demande n'a pas de tarif enregistré : impossible de la valider."
        raise ActiveRecord::Rollback
      end

      lock_slot!

      unless PartyEvent.private_slot_available?(@party_request.held_on, @party_request.slot)
        @errors << "Ce créneau n'est plus disponible (capacité atteinte, blocage ou Pizza party publique)."
        raise ActiveRecord::Rollback
      end

      party_event = PartyEvent.create!(
        kind: :private_party,
        held_on: @party_request.held_on,
        slot: @party_request.slot
      )

      @order = build_order(party_event)

      @party_request.update!(
        state: :accepted,
        order: @order,
        decided_at: Time.current,
        decided_by: @decided_by
      )
    end

    return false if @errors.any?

    PartyRequestNotifier.request_accepted(@party_request)
    @order
  end

  # Refuse la demande. Le motif est obligatoire : c'est la seule explication que
  # le client recevra.
  def refuse(reason)
    @errors = []
    reason = reason.to_s.strip

    if reason.blank?
      @errors << "Merci d'indiquer la raison du refus : elle est envoyée au client."
      return false
    end

    ActiveRecord::Base.transaction do
      @party_request.lock!

      unless @party_request.state_pending?
        @errors << already_handled_message
        raise ActiveRecord::Rollback
      end

      @party_request.update!(
        state: :refused,
        decided_at: Time.current,
        decided_by: @decided_by,
        decision_reason: reason
      )
    end

    return false if @errors.any?

    PartyRequestNotifier.request_refused(@party_request)
    true
  end

  # Retire une validation tant que rien n'est payé : la commande est annulée, le
  # créneau rendu, le client prévenu avec le motif.
  def retract(reason)
    @errors = []
    reason = reason.to_s.strip

    if reason.blank?
      @errors << "Merci d'indiquer la raison : elle est envoyée au client."
      return false
    end

    order = @party_request.order

    if order.nil? || !order.awaiting_payment?
      @errors << "Cette réservation ne peut plus être retirée (elle est payée ou déjà annulée)."
      return false
    end

    PartyReservationRelease.new(order).call(cancel_payment_intent: true)
    @party_request.update!(state: :refused, decision_reason: reason, decided_at: Time.current, decided_by: @decided_by)

    PartyRequestNotifier.request_retracted(@party_request)
    true
  end

  private

  def already_handled_message
    if @party_request.decided_at
      "Cette demande a déjà été traitée par #{@party_request.decided_by} le #{I18n.l(@party_request.decided_at, format: :short)}."
    else
      "Cette demande a déjà été traitée."
    end
  end

  def build_order(party_event)
    items = @party_request.party_request_items.includes(:product_variant).to_a
    total = items.sum(&:total_cents)

    order = Order.create!(
      customer: @party_request.customer,
      party_event: party_event,
      bake_day: nil,
      source: :party,
      status: :awaiting_payment,
      total_cents: total,
      group_name: @party_request.group_name,
      customer_note: @party_request.customer_note,
      payment_due_at: payment_due_at
    )

    items.each do |item|
      order.order_items.create!(
        product_variant: item.product_variant,
        qty: item.qty,
        unit_price_cents: item.unit_price_cents
      )
    end

    order
  end

  # Échéance de paiement : le CUT-OFF de la fournée qui pétrira les pâtons.
  # C'est le moment où la boulangerie fige sa production — un nombre de
  # participants arrivé après n'a plus personne pour le pétrir.
  #
  # Validation tardive (après l'instant de sollicitation, voire après le
  # cut-off) : le client garde au moins 24 h pour répondre, sans jamais déborder
  # le début de la party.
  def payment_due_at
    cut_off = @party_request.deadline_at
    prompt = @party_request.payment_prompt_at

    return cut_off if cut_off && prompt && Time.current < prompt

    [ Time.current + 24.hours, party_start_at ].min
  end

  def party_start_at
    date = @party_request.held_on
    ActiveSupport::TimeZone[PartyRequest::DEADLINE_ZONE].local(date.year, date.month, date.day, 18, 0, 0)
  end

  def lock_slot!
    key = Integer(@party_request.held_on.jd) * 2 + Integer(PartyEvent.slots.fetch(@party_request.slot))
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?, ?)", LOCK_NAMESPACE, key ])
    )
  end
end
