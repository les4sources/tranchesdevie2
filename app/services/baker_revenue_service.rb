# frozen_string_literal: true

# Moteur de calcul des revenus des boulangers (#54).
#
# Pour chaque JOUR DE PRODUCTION (BakeDay) de la période, calcule :
#   - CA            = somme des commandes finalisées (paid/ready/picked_up) du jour
#   - coûtant       = Σ (prix coûtant variante #90 à la date du jour × quantité)
#                     sur les articles de PAIN produits maison
#   - sacs          = Σ coût des sacs à pains des commandes du jour (#52)
#   - transport     = coût de transport du jour (paramètre historisé #54)
#   - marge brute   = CA − coûtant − sacs − transport
#   - part 4 Sources = taux 4S (historisé, réf. 30 %) × marge brute
#   - pool boulangers = marge brute − part 4 Sources (réf. 70 %)
#   - revenu/artisan  = pool × (part littérale de l'artisan présent / 100)
#
# Décisions de design (consolidation finale Michael, 25/06/2026) :
#   - La part de chaque artisan est LITTÉRALE (pas de normalisation). Si la somme
#     des parts des artisans PRÉSENTS un jour dépasse 100 %, on lève un
#     avertissement (`warnings`) mais on NE corrige PAS automatiquement.
#   - Les paramètres (transport, taux 4S, % artisan) sont historisés par date :
#     un nouveau palier n'affecte jamais les périodes antérieures. La date de
#     référence d'un jour est son `baked_on`.
#   - Le CA et les coûts sont ventilés par jour de cuisson, cohérent avec le
#     reporting des ventes existant (Order.*_between).
#
# Usage :
#   report = BakerRevenueService.new(start_date: d1, end_date: d2).call
#   report.total_revenue_cents
#   report.gross_margin_cents
#   report.days                 # => [ DayBreakdown, ... ] (par jour de production)
#   report.artisan_totals       # => [ ArtisanTotal, ... ] (cumul par artisan)
#   report.warnings             # => [ "…", … ] (sommes de parts > 100 %)
class BakerRevenueService
  # Part attribuée à un artisan présent sur un jour de production donné.
  ArtisanShare = Struct.new(
    :artisan,
    :percent,        # part littérale configurée (BigDecimal), ou nil si non saisie
    :amount_cents,   # pool × percent / 100
    keyword_init: true
  )

  # Détail d'un jour de production.
  DayBreakdown = Struct.new(
    :bake_day,
    :date,
    :revenue_cents,
    :cost_price_cents,
    :bread_bags_cents,
    :transport_cents,
    :gross_margin_cents,
    :four_sources_cents,
    :baker_pool_cents,
    :artisan_shares,        # [ ArtisanShare, ... ]
    :percent_sum,           # somme des parts des artisans présents (BigDecimal)
    :percent_overflow,      # true si percent_sum > 100
    keyword_init: true
  )

  # Cumul d'un artisan sur la période (additionnable par mois).
  ArtisanTotal = Struct.new(
    :artisan,
    :amount_cents,
    :days_count,
    keyword_init: true
  )

  Report = Struct.new(
    :start_date,
    :end_date,
    :days,
    :total_revenue_cents,
    :total_cost_price_cents,
    :total_bread_bags_cents,
    :total_transport_cents,
    :gross_margin_cents,
    :four_sources_cents,
    :baker_pool_cents,
    :artisan_totals,
    :warnings,
    keyword_init: true
  )

  # Statuts de commande pris en compte dans le CA (mêmes que Order.completed :
  # paid / ready / picked_up). Les commandes annulées, planifiées ou en attente
  # sont exclues.
  def initialize(start_date:, end_date:)
    @start_date = start_date
    @end_date = end_date
  end

  def call
    days = bake_days.map { |bake_day| build_day(bake_day) }

    Report.new(
      start_date: @start_date,
      end_date: @end_date,
      days: days,
      total_revenue_cents: sum(days, :revenue_cents),
      total_cost_price_cents: sum(days, :cost_price_cents),
      total_bread_bags_cents: sum(days, :bread_bags_cents),
      total_transport_cents: sum(days, :transport_cents),
      gross_margin_cents: sum(days, :gross_margin_cents),
      four_sources_cents: sum(days, :four_sources_cents),
      baker_pool_cents: sum(days, :baker_pool_cents),
      artisan_totals: consolidate_artisans(days),
      warnings: build_warnings(days)
    )
  end

  private

  def bake_days
    BakeDay
      .where(baked_on: @start_date..@end_date)
      .ordered
      .includes(:baking_artisans)
  end

  def build_day(bake_day)
    date = bake_day.baked_on

    revenue_cents = day_revenue_cents(bake_day)
    cost_price_cents = day_cost_price_cents(bake_day, date)
    bread_bags_cents = day_bread_bags_cents(bake_day)
    transport_cents = RevenueParameter.transport_cents_on(date)

    gross_margin_cents = revenue_cents - cost_price_cents - bread_bags_cents - transport_cents
    four_sources_cents = four_sources_cut(gross_margin_cents, date)
    baker_pool_cents = gross_margin_cents - four_sources_cents

    artisans = bake_day.baking_artisans.to_a
    shares = artisan_shares(artisans, baker_pool_cents, date)
    percent_sum = shares.sum { |share| share.percent || 0 }

    DayBreakdown.new(
      bake_day: bake_day,
      date: date,
      revenue_cents: revenue_cents,
      cost_price_cents: cost_price_cents,
      bread_bags_cents: bread_bags_cents,
      transport_cents: transport_cents,
      gross_margin_cents: gross_margin_cents,
      four_sources_cents: four_sources_cents,
      baker_pool_cents: baker_pool_cents,
      artisan_shares: shares,
      percent_sum: percent_sum,
      percent_overflow: percent_sum > 100
    )
  end

  # CA du jour : somme des commandes finalisées rattachées au jour de cuisson.
  def day_revenue_cents(bake_day)
    bake_day.orders.completed.sum(:total_cents)
  end

  # Coûtant matières premières du jour : Σ (coûtant variante à la date × qty) sur
  # les articles de PAIN produits maison des commandes finalisées. On réutilise
  # le résolveur historisé de #90 (ProductVariant#cost_price_cents). Un coûtant
  # manquant (aucun palier à la date) est traité comme 0 (aucune déduction) —
  # cohérent avec le coût des sacs (#52).
  def day_cost_price_cents(bake_day, date)
    order_items =
      OrderItem
        .joins(:order, product_variant: :product)
        .where(orders: { id: bake_day.orders.completed.select(:id) })
        .where(products: { category: Product.categories[:breads],
                           internal_category: Product.internal_categories[:boulangerie] })
        .includes(product_variant: :variant_cost_prices)

    order_items.sum do |item|
      unit_cost = item.product_variant.cost_price_cents(on: date) || 0
      unit_cost * item.qty
    end
  end

  # Coût total des sacs à pains du jour (#52), à la date de cuisson.
  def day_bread_bags_cents(bake_day)
    bake_day.orders.completed.includes(order_items: { product_variant: :product }).sum do |order|
      order.bread_bags_cost_cents(on: bake_day.baked_on)
    end
  end

  # Part des 4 Sources sur la marge brute (taux historisé en points de base).
  # Si la marge brute est négative, la part suit le signe (les 4 Sources
  # partagent aussi les pertes au prorata) — cohérent avec le partage 30/70.
  def four_sources_cut(gross_margin_cents, date)
    basis_points = RevenueParameter.four_sources_basis_points_on(date)
    (gross_margin_cents * basis_points / 10_000.0).round
  end

  # Répartition du pool entre les artisans présents, au % littéral configuré.
  def artisan_shares(artisans, baker_pool_cents, date)
    artisans.map do |artisan|
      percent = artisan.revenue_share_percent(on: date)
      amount = percent.nil? ? 0 : (baker_pool_cents * percent / 100.0).round

      ArtisanShare.new(artisan: artisan, percent: percent, amount_cents: amount)
    end
  end

  # Cumul par artisan sur l'ensemble des jours (additionnable par mois côté
  # appelant en filtrant la période). Trié par nom pour un affichage stable.
  def consolidate_artisans(days)
    grouped = Hash.new { |hash, key| hash[key] = { artisan: nil, amount_cents: 0, days_count: 0 } }

    days.each do |day|
      day.artisan_shares.each do |share|
        bucket = grouped[share.artisan.id]
        bucket[:artisan] = share.artisan
        bucket[:amount_cents] += share.amount_cents
        bucket[:days_count] += 1
      end
    end

    grouped
      .values
      .map { |bucket| ArtisanTotal.new(**bucket) }
      .sort_by { |total| total.artisan.name }
  end

  def build_warnings(days)
    days.select(&:percent_overflow).map do |day|
      "Le #{I18n.l(day.date)}, la somme des parts des boulangers présents " \
        "atteint #{format_percent(day.percent_sum)} % (> 100 %). " \
        "Les parts sont appliquées telles quelles, sans correction automatique."
    end
  end

  def format_percent(value)
    formatted = value.to_f
    formatted == formatted.to_i ? formatted.to_i.to_s : format("%.2f", formatted)
  end

  def sum(days, attribute)
    days.sum { |day| day.public_send(attribute) }
  end
end
