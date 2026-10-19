# frozen_string_literal: true

# Convertit en VRAIES parties privées les pizza parties enregistrées comme de
# simples commandes de pain (ex. /admin/orders/627).
#
# Avant les événements party (#pizza-parties), une party privée se commandait
# comme un pain : une commande rattachée à une FOURNÉE, avec la ligne « Pizza
# party privée – Nombre de personnes » (+ le forfait). Ces commandes
# n'apparaissent pas dans l'écran Parties, ni dans le filtre `kind=private_party`
# de l'API que lit Claudy.
#
# La conversion fait d'une telle commande ce que `ManualPrivatePartyService`
# aurait créé : un `PartyEvent` privé + sa commande `source: :party` sans
# fournée. La commande est CONSERVÉE (même numéro, mêmes lignes, même total, même
# paiement Stripe ou hors-ligne) : on ne fait que la rattacher à l'événement.
#
# Date par défaut : le jour de la fournée, au SOIR. C'est le seul choix qui ne
# déplace aucun euro — `BakeDaySheetService` et la paie comptent une party du
# soir sur la fournée du jour même (`PartyEvent.prepared_by`), exactement là où
# la commande était comptée avant. Une autre date peut être imposée commande par
# commande (`overrides`), au prix d'un déplacement vers une autre fournée.
#
# Ne convertit PAS (et dit pourquoi) :
#   - une commande annulée : il n'y a pas de party à créer ;
#   - une commande MIXTE (pain + party) : la sortir de sa fournée y retirerait
#     le pain ; elle se scinde à la main.
#
# Aucune notification : ni SMS, ni e-mail équipe, ni post-it du calendrier.
class LegacyPrivatePartyConversionService
  Candidate = Struct.new(:order, :held_on, :slot, :persons, :forfait, :reason, keyword_init: true) do
    def convertible?
      reason.nil?
    end
  end

  # `overrides` : { order_id => { held_on: Date, slot: "soir" } }.
  def initialize(order_ids: nil, overrides: {})
    @order_ids = Array(order_ids).map(&:to_i).presence
    @overrides = overrides.transform_keys(&:to_i)
  end

  # Commandes portant une ligne party privée (pâtons ou forfait) sans événement.
  def candidates
    scope = Order.where(party_event_id: nil)
                 .where(id: OrderItem.joins(product_variant: :product)
                                     .where(products: { pizza_party_role: party_roles })
                                     .select(:order_id))
                 .includes(:customer, :bake_day, :payment, :wallet_transactions, order_items: { product_variant: :product })
                 .order(:id)
    scope = scope.where(id: @order_ids) if @order_ids

    scope.map { |order| build_candidate(order) }
  end

  # Convertit les candidats convertibles. Renvoie les candidats traités.
  def call
    candidates.select(&:convertible?).each { |candidate| convert!(candidate) }
  end

  private

  def party_roles
    [ Product.pizza_party_roles[:party], Product.pizza_party_roles[:forfait] ]
  end

  def build_candidate(order)
    override = @overrides[order.id] || {}
    items = order.order_items
    party_items = items.select { |item| item.product_variant.product.pizza_party_role_party? }

    Candidate.new(
      order: order,
      held_on: override[:held_on] || order.bake_day&.baked_on,
      slot: (override[:slot] || PartyEvent::PRIVATE_SLOT).to_s,
      persons: party_items.sum(&:qty),
      forfait: items.any? { |item| item.product_variant.product.pizza_party_role_forfait? },
      reason: skip_reason(order, items, override)
    )
  end

  def skip_reason(order, items, override)
    return "annulée" if order.cancelled?
    return "mixte (pain + party) : à scinder à la main" if items.any? { |item| item.product_variant.product.pizza_party_role_none? }
    return "aucune date (ni fournée, ni date imposée)" if order.bake_day.nil? && override[:held_on].nil?
    return "créneau inconnu" unless PartyEvent.slots.key?((override[:slot] || PartyEvent::PRIVATE_SLOT).to_s)

    nil
  end

  def convert!(candidate)
    order = candidate.order

    ActiveRecord::Base.transaction do
      event = PartyEvent.create!(kind: :private_party, held_on: candidate.held_on, slot: candidate.slot)
      # `update_columns` et non `update!` : la commande est historique, ses
      # validations de création (lieu de retrait ouvert ce jour-là, etc.) n'ont
      # pas à être rejouées, et rien d'autre qu'elle ne doit bouger.
      order.update_columns(party_event_id: event.id, source: Order.sources[:party],
                           bake_day_id: nil, updated_at: Time.current)
    end

    candidate
  end
end
