# frozen_string_literal: true

# Compta des PIZZA PARTIES PUBLIQUES (#pizza-parties).
#
# Barème confirmé par Michael (19/07/2026), par pâton (1 pâton = 1 personne),
# variante adulte OU enfant. Chaque variante porte une BASE 4 Sources
# (`party_four_sources_base_cents` : 3 € adulte, 2 € enfant) ; la base boulangers
# en découle : base_boulangers = prix public − base 4 Sources (7 € adulte,
# 4 € enfant).
#
# La base boulangers (moins le coûtant du pâton) est ensuite partagée comme du
# pain : boulangers 70 %, 4 Sources 30 % (taux 4S historisé de l'app). La base
# 4 Sources s'ajoute par-dessus. Pas de forfait en public.
#
#   marge          = base_boulangers − coûtant
#   part 4 Sources = base_4S + (taux 4S × marge)
#   part boulangers = marge − (taux 4S × marge)
#
# Réconcilie par unité : part 4 Sources + part boulangers = prix − coûtant.
#
# Usage : PublicPartyRevenueService.call(bake_day.orders.completed)
class PublicPartyRevenueService
  Result = Struct.new(
    :persons,
    :party_orders_count,
    :sale_cents,
    :dough_cost_cents,
    :four_sources_cents,
    :bakers_cents,
    keyword_init: true
  ) do
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
      items = order.order_items.select { |item| public_party_item?(item) }
      next if items.empty?

      party_orders += 1
      date = order.bake_day&.baked_on || Date.current
      rate = four_sources_rate(date)

      items.each do |item|
        qty = item.qty
        variant = item.product_variant
        price = item.unit_price_cents
        base_four_sources = variant.party_four_sources_base_cents || 0
        unit_cost = variant.cost_price_cents(on: date) || 0

        margin = (price - base_four_sources) - unit_cost # base boulangers − coûtant
        four_sources_share = (margin * rate).round

        persons += qty
        sale += price * qty
        dough_cost += unit_cost * qty
        four_sources += (base_four_sources + four_sources_share) * qty
        bakers += (margin - four_sources_share) * qty
      end
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

  private

  def public_party_item?(item)
    item.product_variant.product.pizza_party_role_public_party?
  end

  # Taux 4 Sources (historisé) exprimé en fraction (0,30 par défaut).
  def four_sources_rate(date)
    RevenueParameter.four_sources_basis_points_on(date) / 10_000.0
  end
end
