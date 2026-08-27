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

  # Parties PUBLIQUES que cette fournée prépare : celles tenues du jour de la
  # fournée (inclus) jusqu'à la fournée suivante (exclue) — sans fournée
  # suivante, tout ce qui vient après lui revient.
  #
  # Une party publique se tient toujours en soirée : la règle est donc celle des
  # parties privées du soir (`PartyEvent#preparation_bake_day`), la fournée du
  # jour même si elle existe, sinon la dernière qui précède. L'intervalle est
  # semi-ouvert, donc chaque party publique n'a qu'UNE fournée : la plus grande
  # `baked_on` inférieure ou égale à sa date. Une party antérieure à toute
  # fournée n'est rattachée à aucune — comme une party privée orpheline.
  def public_event_ids
    date = @bake_day.baked_on
    next_date = BakeDay.where("baked_on > ?", date).order(:baked_on).limit(1).pick(:baked_on)

    scope = PartyEvent.public_events.not_deleted
    scope = next_date ? scope.where(held_on: date...next_date) : scope.where(held_on: date..)
    scope.pluck(:id)
  end
end
