# frozen_string_literal: true

# Moteur de calcul des revenus des boulangers (#54).
#
# Pour chaque JOUR DE PRODUCTION (BakeDay) de la période, calcule :
#   - CA            = somme des commandes finalisées (paid/ready/picked_up) du jour
#   - coûtant       = Σ (prix coûtant variante #90 à la date du jour × quantité)
#                     sur les articles de PAIN produits maison
#   - sacs          = Σ coût des sacs à pains des commandes du jour (#52)
#   - transport     = coût de transport du jour (paramètre historisé #54)
#   - commissions   = Σ commissions Stripe des commandes EN LIGNE du jour
#                     (cohérent avec Order.stripe_fees_between ; cash/portefeuille
#                     n'ont pas de commission)
#   - marge brute   = CA − coûtant − sacs − transport − commissions
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
    :commission_cents,
    :gross_margin_cents,
    :four_sources_cents,
    :baker_pool_cents,
    :artisan_shares,        # [ ArtisanShare, ... ]
    :percent_sum,           # somme des parts des artisans présents (BigDecimal)
    :percent_overflow,      # true si percent_sum > 100
    keyword_init: true
  )

  # Cumul BRUT d'un artisan sur la période (avant mise en commun des
  # partenariats) : somme des parts de SES propres jours de production.
  # Additionnable par mois.
  ArtisanTotal = Struct.new(
    :artisan,
    :amount_cents,
    :days_count,
    keyword_init: true
  )

  # Revenu FINAL d'un artisan sur la période, après application de la couche
  # partenariat (#54). Pour un artisan hors partenariat, `settled_cents` égale
  # `raw_cents` (il garde son brut). Pour un membre de partenariat, le brut de
  # tous les membres est mis en commun puis réparti au poids : `settled_cents`
  # peut donc différer de `raw_cents` (c'est tout l'intérêt : égaliser les bons
  # et les mauvais jours entre partenaires).
  ArtisanSettlement = Struct.new(
    :artisan,
    :partnership,     # RevenuePartnership, ou nil si l'artisan est solo
    :raw_cents,       # brut de ses propres jours (avant mise en commun)
    :settled_cents,   # revenu final après mise en commun/répartition
    :days_count,      # nombre de ses jours de production sur la période
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
    :total_commission_cents,
    :gross_margin_cents,
    :four_sources_cents,
    :baker_pool_cents,
    :artisan_totals,       # cumul BRUT par artisan (avant partenariats)
    :artisan_settlements,  # revenu FINAL par artisan (après mise en commun)
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
    artisan_totals = consolidate_artisans(days)

    Report.new(
      start_date: @start_date,
      end_date: @end_date,
      days: days,
      total_revenue_cents: sum(days, :revenue_cents),
      total_cost_price_cents: sum(days, :cost_price_cents),
      total_bread_bags_cents: sum(days, :bread_bags_cents),
      total_transport_cents: sum(days, :transport_cents),
      total_commission_cents: sum(days, :commission_cents),
      gross_margin_cents: sum(days, :gross_margin_cents),
      four_sources_cents: sum(days, :four_sources_cents),
      baker_pool_cents: sum(days, :baker_pool_cents),
      artisan_totals: artisan_totals,
      artisan_settlements: build_settlements(artisan_totals),
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
    # Pas de vente ce jour-là (CA = 0) → aucun transport facturé : pas de
    # fournée, donc pas de tournée. La marge brute (et le revenu net) reste à 0.
    transport_cents = revenue_cents.zero? ? 0 : RevenueParameter.transport_cents_on(date)
    # Commissions Stripe des commandes EN LIGNE du jour (CA = 0 → aucune commande
    # → commission naturellement 0 : pas de paiement Stripe à déduire).
    commission_cents = day_commission_cents(date)

    gross_margin_cents =
      revenue_cents - cost_price_cents - bread_bags_cents - transport_cents - commission_cents
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
      commission_cents: commission_cents,
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

  # Commissions Stripe du jour : somme des `payments.stripe_fee_cents` des
  # commandes finalisées EN LIGNE rattachées au jour de cuisson. Même logique
  # que Order.stripe_fees_between, restreinte à une seule date (`baked_on`).
  # Les commandes cash/portefeuille n'ont pas de Payment Stripe (le `joins`
  # les exclut) et une commission non encore connue est NULL (non sommée) → un
  # jour sans paiement Stripe donne naturellement 0.
  def day_commission_cents(date)
    Order.stripe_fees_between(date, date)
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

  # Couche partenariat (#54) : à partir des cumuls BRUTS par artisan, produit le
  # revenu FINAL par artisan.
  #   - Membres d'un même partenariat : leurs bruts sont mis en commun puis
  #     répartis au poids (parts égales par défaut). Tous les membres du
  #     partenariat reçoivent une part, même absents sur la période (brut 0) —
  #     tant qu'AU MOINS un membre a produit (sinon le partenariat n'apparaît
  #     pas). C'est le partage « toujours 50/50, même absent ».
  #   - Artisan hors partenariat : son revenu final = son brut (solo).
  # Trié par nom pour un affichage stable.
  def build_settlements(artisan_totals)
    raw_by_id = artisan_totals.index_by { |total| total.artisan.id }
    settlements = []
    covered_ids = []

    partnerships.each do |partnership|
      memberships = partnership.revenue_partnership_memberships.to_a
      next if memberships.empty?
      # Le partenariat n'apparaît que si au moins un membre a produit sur la
      # période (évite d'afficher des lignes à 0 pour un mois où le duo n'a pas
      # boulangé).
      next unless memberships.any? { |ms| raw_by_id.key?(ms.artisan_id) }

      pooled_cents = memberships.sum { |ms| raw_by_id[ms.artisan_id]&.amount_cents || 0 }
      shares = distribute(pooled_cents, memberships.map(&:weight))

      memberships.each_with_index do |ms, index|
        raw = raw_by_id[ms.artisan_id]
        settlements << ArtisanSettlement.new(
          artisan: ms.artisan,
          partnership: partnership,
          raw_cents: raw&.amount_cents || 0,
          settled_cents: shares[index],
          days_count: raw&.days_count || 0
        )
        covered_ids << ms.artisan_id
      end
    end

    # Artisans ayant produit mais membres d'aucun partenariat → solo, brut = final.
    artisan_totals.each do |total|
      next if covered_ids.include?(total.artisan.id)

      settlements << ArtisanSettlement.new(
        artisan: total.artisan,
        partnership: nil,
        raw_cents: total.amount_cents,
        settled_cents: total.amount_cents,
        days_count: total.days_count
      )
    end

    settlements.sort_by { |settlement| settlement.artisan.name }
  end

  # Partenariats actifs, avec membres et artisans préchargés.
  def partnerships
    RevenuePartnership
      .active
      .ordered
      .includes(revenue_partnership_memberships: :artisan)
  end

  # Répartit `total_cents` (peut être négatif : partage des pertes) entre des
  # membres au prorata de `weights`, en cents entiers dont la somme égale
  # EXACTEMENT `total_cents`. La dérive d'arrondi (au plus quelques cents) est
  # absorbée par le membre au poids le plus élevé.
  def distribute(total_cents, weights)
    weight_sum = weights.sum
    return Array.new(weights.size, 0) if weights.empty? || weight_sum.zero?

    shares = weights.map { |weight| (total_cents * weight / weight_sum.to_f).round }
    drift = total_cents - shares.sum
    heaviest_index = weights.each_with_index.max_by { |weight, _| weight }.last
    shares[heaviest_index] += drift
    shares
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
