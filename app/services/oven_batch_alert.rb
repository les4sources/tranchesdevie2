# frozen_string_literal: true

# Alerte « Capacité four » (Claire, 28/09/2026). Une journée démarre à deux
# fournées de pain (65 kg chacune depuis le 29/09, cf.
# `BatchProposalService::CAPACITY_GRAMS`). 10 kg avant qu'elles soient pleines,
# les boulangers doivent choisir, en connaissance de cause :
#   - rester à deux fournées pleines ;
#   - ou ouvrir une 3e fournée, donc allonger leur horaire de production.
#
# La boutique garde sa propre limite (`BakeDay#oven_capacity_grams`, 110 kg ou
# 165 kg les jours de marché) : ce sont surtout les commandes ajoutées en
# interne qui poussent le four au-delà. Pas de 4e fournée, donc pas d'alerte
# une fois la 3e ouverte.
#
# Le poids compté est celui de la jauge « Capacité four » : les pains des
# commandes non annulées, sans les pâtons, qui cuisent au four à bois.
class OvenBatchAlert
  BATCH_GRAMS = BatchProposalService::CAPACITY_GRAMS
  DEFAULT_BATCHES = 2
  THIRD_BATCH = 3
  TWO_BATCHES_GRAMS = DEFAULT_BATCHES * BATCH_GRAMS
  # 10 kg sous deux fournées pleines : assez tôt pour décider avant d'y être.
  ALERT_GRAMS = TWO_BATCHES_GRAMS - 10_000
  TWO_BATCHES_KG = TWO_BATCHES_GRAMS / 1_000
  ALERT_KG = ALERT_GRAMS / 1_000

  attr_reader :bake_day, :oven_grams

  # Poids de pain au four par jour de cuisson, en une seule requête : le
  # bandeau de l'admin le calcule sur chaque page.
  def self.oven_grams_by_bake_day(bake_day_ids)
    return {} if bake_day_ids.empty?

    OrderItem.joins(:order, product_variant: :product)
             .where(orders: { bake_day_id: bake_day_ids })
             .where.not(orders: { status: :cancelled })
             .where(products: { category: Product.categories[:breads] })
             .group("orders.bake_day_id")
             .sum("order_items.qty * COALESCE(product_variants.flour_quantity, 0)")
  end

  # Jours à venir qui attendent une décision, pour le bandeau de l'admin.
  def self.pending(scope = BakeDay.future.ordered)
    days = scope.to_a
    grams = oven_grams_by_bake_day(days.map(&:id))

    days.map { |day| new(day, grams.fetch(day.id, 0)) }.select(&:action_needed?)
  end

  def self.for(bake_day)
    new(bake_day, oven_grams_by_bake_day([ bake_day.id ]).fetch(bake_day.id, 0))
  end

  def initialize(bake_day, oven_grams)
    @bake_day = bake_day
    @oven_grams = oven_grams.to_i
  end

  # :quiet            — sous le seuil d'alerte, rien à décider ;
  # :decision_needed  — seuil atteint, pas encore de choix ;
  # :two_batches      — deux fournées pleines validées, et ça tient ;
  # :over_two_batches — deux fournées validées, mais le four les dépasse ;
  # :third_batch      — 3e fournée ouverte.
  def state
    case bake_day.oven_batch_plan
    when THIRD_BATCH then :third_batch
    when DEFAULT_BATCHES then oven_grams > TWO_BATCHES_GRAMS ? :over_two_batches : :two_batches
    else oven_grams >= ALERT_GRAMS ? :decision_needed : :quiet
    end
  end

  def action_needed?
    %i[decision_needed over_two_batches].include?(state)
  end

  # Rester à deux fournées n'a de sens que si le pain y tient encore.
  def two_batches_possible?
    oven_grams <= TWO_BATCHES_GRAMS
  end

  def remaining_grams
    [ TWO_BATCHES_GRAMS - oven_grams, 0 ].max
  end

  def excess_grams
    [ oven_grams - TWO_BATCHES_GRAMS, 0 ].max
  end
end
