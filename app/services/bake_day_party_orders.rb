# frozen_string_literal: true

# Commandes PARTY qu'une fournée doit préparer (#207).
#
# Une réservation de party faite en ligne est créée avec `bake_day: nil` — par
# design : une party n'est pas datée par une fournée mais par son événement.
# Le lien avec la fournée qui pétrit ses pâtons passe donc par l'événement
# (`PartyEvent.prepared_by`), jamais par la commande.
#
# Le tableau de bord du jour utilisait déjà cette réciproque — c'est pourquoi il
# annonçait bien « 11 pâtons à préparer ». Le calcul des revenus, lui, partait
# de `bake_day.orders`, qui ne contient pas ces commandes : les deux ne se
# rejoignaient jamais, et toute party réservée en ligne échappait à la compta.
#
# Cette classe est désormais la SOURCE UNIQUE des deux côtés : le tableau de
# bord et `BakerRevenueService` posent la même question, donc ils ne peuvent
# plus diverger.
#
# Non-doublon : `prepared_by` attribue chaque party privée à exactement une
# fournée (la soirée du jour même, ou l'intervalle jusqu'à la fournée suivante,
# midi de celle-ci inclus). Les parties PUBLIQUES suivent la même règle, à la
# fournée du jour même ou, à défaut, à la dernière qui précède : leur date se
# choisit dans un champ libre côté admin, sans contrainte de jour de cuisson.
# Sur une égalité stricte `held_on = baked_on`, une party publique posée un jour
# sans fournée sortait INTÉGRALEMENT des revenus des boulangers.
# Les appelants dédupliquent en plus par id, pour le cas d'une commande qui
# porterait à la fois une fournée et un événement.
class BakeDayPartyOrders
  # Statuts « de production » : ce que la fournée doit préparer, y compris ce
  # qui n'est pas encore payé.
  PRODUCTION_STATUSES = %i[unpaid paid ready picked_up planned].freeze

  def self.production(bake_day)
    new(bake_day, statuses: PRODUCTION_STATUSES).call
  end

  # Statuts « finalisés » : ce qui compte en comptabilité (mêmes que
  # `Order.completed`).
  def self.completed(bake_day)
    new(bake_day, statuses: %i[paid ready picked_up]).call
  end

  def initialize(bake_day, statuses:)
    @bake_day = bake_day
    @statuses = statuses
  end

  def call
    return [] if @bake_day&.baked_on.blank?

    event_ids = PartyEvent.prepared_by(@bake_day).pluck(:id) + public_event_ids

    return [] if event_ids.empty?

    Order.where(source: :party, status: @statuses)
         .joins(:party_event)
         .where(party_events: { id: event_ids })
         .includes(order_items: {
                     product_variant: [
                       :mold_type,
                       { variant_cost_prices: [] },
                       { product: { product_flours: :flour } }
                     ]
                   })
         .to_a
  end

  private

  # Parties PUBLIQUES que cette fournée prépare — la règle vit dans
  # `PartyEvent.public_prepared_by`, partagée avec le calcul des revenus.
  #
  # Les événements HISTORIQUES (BilletWeb) en sont exclus : leur compta vient
  # d'un agrégat porté par l'événement, pas de commandes. S'ils en portaient
  # malgré tout, elles seraient comptées deux fois.
  def public_event_ids
    PartyEvent.public_prepared_by(@bake_day).where(historical_source: nil).pluck(:id)
  end
end
