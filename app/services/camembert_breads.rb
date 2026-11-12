# frozen_string_literal: true

# Pains à fournir aux Camembert Parties qu'une fournée prépare (#camembert-parties).
#
# Une Camembert Party ne demande AUCUN pâton : ses places (adulte/enfant) ne
# sont qu'une inscription. La boulangerie fournit en revanche un grand froment
# 1 kg pour cinq convives, adultes et enfants confondus, arrondi au pain
# supérieur — sur l'ÉVÉNEMENT entier, pas commande par commande.
#
# SOURCE UNIQUE du calcul : le tableau de la fournée (quantités, pâte, levain)
# et `BakeCapacityService` (moules, pétrin, four) partent des mêmes entrées,
# sinon les moules oubliaient ces pains quand la pâte les comptait.
class CamembertBreads
  Entry = Struct.new(:party_event, :persons, :bread_count, :variant, :anchor_order, keyword_init: true)

  # `party_orders` : commandes party de la fournée (BakeDayPartyOrders.production).
  def initialize(party_orders, variant: ProductionSetting.current.camembert_bread_variant)
    @party_orders = party_orders
    @variant = variant
  end

  def entries
    @entries ||= @party_orders
      .select { |order| order.party_event&.bread_only? }
      .group_by(&:party_event)
      .map do |event, event_orders|
        persons = event_orders.sum(&:party_paton_count)
        Entry.new(party_event: event,
                  persons: persons,
                  bread_count: PartyEvent.camembert_bread_count(persons),
                  variant: @variant,
                  anchor_order: event_orders.min_by(&:id))
      end
      .sort_by { |entry| entry.party_event.held_on }
  end

  # Lignes CALCULÉES, jamais enregistrées : elles pèsent sur la production
  # sans toucher aux commandes ni au chiffre d'affaires.
  def order_items
    entries.filter_map do |entry|
      next if entry.variant.nil? || entry.bread_count.zero?

      OrderItem.new(order_id: entry.anchor_order.id,
                    product_variant: entry.variant,
                    qty: entry.bread_count,
                    unit_price_cents: 0)
    end
  end
end
