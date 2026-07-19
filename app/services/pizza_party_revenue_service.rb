# frozen_string_literal: true

# Compta des PIZZA PARTIES PRIVÉES (#pizza-parties).
#
# Les parties privées ne suivent PAS le partage 70/30 des pains : elles ont un
# barème spécifique (note de Stéphanie, confirmé par Michael le 19/07/2026).
#
# Prix de vente : 5 €/personne (1 personne = 1 pâton) + 40 € de forfait.
#
# Répartition, pour N personnes (N pâtons) sur une commande party :
#   - 4 Sources  = N × (1 € + 30 % × prix pâton normal) + 10 € (part forfait)
#   - Boulangers = N × (4 € − coûtant du pâton − 30 % × prix pâton normal) + 30 €
#
# Le « prix pâton normal » est le prix de vente au détail d'un pâton
# (« Boule de pâte à pizza à emporter », 2 €) : les 30 % (0,60 €) sont un bonus
# 4 Sources, retiré de la part boulangers. Le coûtant du pâton (matière) est la
# vraie dépense, retirée de la part boulangers ; il réconcilie le tout :
# vente − Σ coûtant = part 4 Sources + part boulangers.
#
# Le forfait (30 € boulangers / 10 € 4 Sources) n'est compté que si la commande
# porte effectivement la ligne forfait (auto-synchronisée par
# PizzaPartyForfaitService), donc jamais pour une commande party sans forfait.
#
# Barème et prix de référence sont des constantes ici (valeurs de la feuille de
# Stéphanie) ; ils pourront devenir des paramètres historisés (RevenueParameter)
# si le besoin apparaît.
#
# Usage :
#   result = PizzaPartyRevenueService.call(bake_day.orders.completed)
#   result.persons, result.four_sources_cents, result.bakers_cents, ...
#
# Les appelants qui bouclent sur beaucoup de commandes doivent précharger
# `order_items: { product_variant: [:variant_cost_prices, :product] }` et
# `:bake_day` pour éviter les N+1.
class PizzaPartyRevenueService
  BAKERS_PER_PERSON_CENTS = 400          # 4 €/personne (base boulangers)
  FOUR_SOURCES_PER_PERSON_CENTS = 100    # 1 €/personne (base 4 Sources)
  NORMAL_PATON_PRICE_CENTS = 200         # prix de vente normal d'un pâton (2 €)
  FOUR_SOURCES_PATON_RATE = 0.30         # 30 % du pâton normal → bonus 4 Sources
  FORFAIT_BAKERS_CENTS = 3000            # 30 € du forfait aux boulangers
  FORFAIT_FOUR_SOURCES_CENTS = 1000      # 10 € du forfait aux 4 Sources

  Result = Struct.new(
    :persons,              # nombre total de personnes (pâtons) sur les commandes party
    :party_orders_count,   # nombre de commandes contenant une party
    :sale_cents,           # CA party (pâtons + forfaits)
    :dough_cost_cents,     # coûtant total des pâtons
    :four_sources_cents,   # part 4 Sources
    :bakers_cents,         # part boulangers
    keyword_init: true
  ) do
    # Marge distribuée (4 Sources + boulangers). Doit égaler CA − coûtant.
    def distributed_cents
      four_sources_cents + bakers_cents
    end
  end

  def self.call(orders)
    new(orders).call
  end

  def initialize(orders)
    @orders = orders.to_a
  end

  def call
    persons = 0
    party_orders = 0
    sale = 0
    dough_cost = 0
    four_sources = 0
    bakers = 0

    @orders.each do |order|
      party_items = order.order_items.select { |item| party_item?(item) }
      next if party_items.empty?

      party_orders += 1
      date = order.bake_day&.baked_on || Date.current

      party_items.each do |item|
        qty = item.qty
        unit_cost = item.product_variant.cost_price_cents(on: date) || 0

        persons += qty
        sale += item.unit_price_cents * qty
        dough_cost += unit_cost * qty
        four_sources += qty * (FOUR_SOURCES_PER_PERSON_CENTS + paton_bonus_cents)
        bakers += qty * (BAKERS_PER_PERSON_CENTS - unit_cost - paton_bonus_cents)
      end

      forfait_items = order.order_items.select { |item| forfait_item?(item) }
      next if forfait_items.empty?

      sale += forfait_items.sum { |item| item.unit_price_cents * item.qty }
      four_sources += FORFAIT_FOUR_SOURCES_CENTS
      bakers += FORFAIT_BAKERS_CENTS
    end

    Result.new(
      persons: persons,
      party_orders_count: party_orders,
      sale_cents: sale,
      dough_cost_cents: dough_cost,
      four_sources_cents: four_sources,
      bakers_cents: bakers
    )
  end

  # Bonus 4 Sources par pâton : 30 % du prix pâton normal (retiré aux boulangers).
  def self.paton_bonus_cents
    (NORMAL_PATON_PRICE_CENTS * FOUR_SOURCES_PATON_RATE).round
  end

  private

  def paton_bonus_cents
    self.class.paton_bonus_cents
  end

  def party_item?(item)
    item.product_variant.product.pizza_party_role_party?
  end

  def forfait_item?(item)
    item.product_variant.product.pizza_party_role_forfait?
  end
end
