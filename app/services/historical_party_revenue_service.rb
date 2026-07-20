# frozen_string_literal: true

# Compta des PIZZA PARTIES PUBLIQUES HISTORIQUES (#pizza-parties).
#
# Avant le passage 100 % par le site, ces parties étaient vendues via BilletWeb et
# l'argent arrivait intégralement sur le compte de la fondation Les 4 Sources, sans
# passer par le split boulangers. Michael a choisi d'appliquer RÉTROACTIVEMENT le
# barème public : à partir des comptes agrégés (adultes/enfants) stockés sur
# l'événement, on calcule la part que les boulangers auraient dû toucher — c.-à-d.
# ce que la fondation 4S leur doit pour ces parties.
#
# Les garnitures BilletWeb sont volontairement ignorées (gérées côté 4S).
# Le coûtant par pâton est celui configuré dans l'app (même barème que les parties
# futures) via ProductVariant#cost_price_cents.
#
#   part 4 Sources (barème) + part boulangers = CA (places) − coûtant
#   net encaissé par 4S     = CA (places) − frais BilletWeb
#   4S après paiement boulangers = net encaissé − part boulangers due
#
# Usage : HistoricalPartyRevenueService.call(party_event)
class HistoricalPartyRevenueService
  Result = Struct.new(
    :persons,
    :adults,
    :children,
    :sale_cents,          # CA brut des places (adultes + enfants)
    :dough_cost_cents,    # coûtant total (pâtons)
    :four_sources_cents,  # part 4 Sources selon le barème
    :bakers_cents,        # part boulangers due selon le barème
    :fees_cents,          # frais BilletWeb absorbés par 4S
    :net_to_four_sources_cents,        # ce que 4S a réellement encaissé (CA − frais)
    :four_sources_effective_cents,     # ce que 4S garde après paiement des boulangers
    keyword_init: true
  )

  def self.call(event)
    new(event).call
  end

  def initialize(event)
    @event = event
  end

  def call
    adults = @event.historical_adults.to_i
    children = @event.historical_children.to_i
    fees = @event.historical_fees_cents.to_i
    date = @event.held_on
    rate = PublicPartyRevenueService.rate_on(date)

    adulte = variant_for("adulte")
    enfant = variant_for("enfant")

    sale = dough = four_sources = bakers = 0

    [ [ adulte, adults ], [ enfant, children ] ].each do |variant, count|
      next if variant.nil? || count.zero?

      split = PublicPartyRevenueService.unit_split(price: variant.price_cents, variant: variant, date: date, rate: rate)
      sale += variant.price_cents * count
      dough += split[:cost] * count
      four_sources += split[:four_sources] * count
      bakers += split[:bakers] * count
    end

    net_to_4s = sale - fees

    Result.new(
      persons: adults + children,
      adults: adults,
      children: children,
      sale_cents: sale,
      dough_cost_cents: dough,
      four_sources_cents: four_sources,
      bakers_cents: bakers,
      fees_cents: fees,
      net_to_four_sources_cents: net_to_4s,
      four_sources_effective_cents: net_to_4s - bakers
    )
  end

  private

  # Variante adulte/enfant du produit « pizza party publique ». Mémoïsé.
  def variant_for(name)
    @variants ||= public_party_product&.product_variants&.index_by(&:name) || {}
    @variants[name]
  end

  def public_party_product
    @public_party_product ||= Product.where(pizza_party_role: Product.pizza_party_roles[:public_party]).first
  end
end
