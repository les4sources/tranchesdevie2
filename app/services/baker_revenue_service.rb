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
#   - lieux de vente = Σ coûts des lieux de vente liés à la fournée (#150),
#                     résolus à la date de la fournée (0 si aucun lieu lié)
#   - marge brute   = CA − coûtant − sacs − transport − commissions − lieux de vente
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
  # Les quatre postes de revenu d'un boulanger, dans l'ordre d'affichage. Leur
  # somme fait toujours son total : c'est l'invariant que tient tout le service.
  BUCKETS = %i[bread_cents private_party_cents public_party_cents workshop_cents].freeze

  # Part attribuée à un artisan présent sur un jour de production donné.
  # Les quatre postes sont calculés séparément puis additionnés, jamais l'inverse :
  # ventiler un total a posteriori réintroduirait un arrondi par poste, et la
  # somme des colonnes ne retomberait plus sur le total affiché.
  ArtisanShare = Struct.new(
    :artisan,
    :percent,               # part littérale configurée (BigDecimal), ou nil si non saisie
    :bread_cents,           # pool pain × percent / 100
    :private_party_cents,   # pool party privée × percent / 100
    :public_party_cents,    # pool party publique (live + historique) × percent / 100
    :amount_cents,          # somme des trois
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
    :sales_locations_cents,
    :gross_margin_cents,
    :four_sources_cents,
    :baker_pool_cents,
    # Pizza parties privées (#pizza-parties) : part calculée hors 70/30, via le
    # barème spécial (PizzaPartyRevenueService), et INCLUSE dans four_sources_cents
    # / baker_pool_cents ci-dessus. Ces champs isolent la contribution party.
    :party_persons,
    :party_revenue_cents,
    :party_four_sources_cents,
    :party_bakers_cents,
    # Idem pour la party PUBLIQUE (variantes adulte/enfant), également incluse
    # dans four_sources_cents / baker_pool_cents.
    :public_party_persons,
    :public_party_revenue_cents,
    :public_party_four_sources_cents,
    :public_party_bakers_cents,
    # Parties publiques HISTORIQUES (BilletWeb). Leur recette n'a jamais transité
    # par l'app : elle est absente de `revenue_cents`, mais la part boulangers due
    # par la fondation entre bien dans `baker_pool_cents` et dans la marge brute.
    :historical_party_persons,
    :historical_party_revenue_cents,
    :historical_party_four_sources_cents,
    :historical_party_bakers_cents,
    # Le pool est ventilé en trois postes pour la répartition par boulanger.
    :bread_pool_cents,
    :private_party_pool_cents,
    :public_party_pool_cents,
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
    # Ventilation du brut. Les ateliers sont un quatrième poste, pas un
    # sous-ensemble du pain : sans eux, la somme des colonnes ne ferait pas
    # le total.
    :bread_cents,
    :private_party_cents,
    :public_party_cents,
    :workshop_cents,
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
    # Ventilation du revenu FINAL, poste par poste. Chaque poste est mis en
    # commun et réparti séparément, si bien que leur somme retombe exactement
    # sur `settled_cents`, partenariat ou pas.
    :bread_cents,
    :private_party_cents,
    :public_party_cents,
    :workshop_cents,
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
    :total_sales_locations_cents,
    :gross_margin_cents,
    :four_sources_cents,
    :baker_pool_cents,
    # Cumuls pizza parties privées (inclus dans four_sources_cents / baker_pool_cents).
    :total_party_persons,
    :total_party_revenue_cents,
    :total_party_four_sources_cents,
    :total_party_bakers_cents,
    :total_public_party_persons,
    :total_public_party_revenue_cents,
    :total_public_party_four_sources_cents,
    :total_public_party_bakers_cents,
    # Parties publiques historiques (BilletWeb) : ce que la fondation doit aux
    # boulangers, appliqué rétroactivement au barème public.
    :total_historical_party_persons,
    :total_historical_party_revenue_cents,
    :total_historical_party_four_sources_cents,
    :total_historical_party_bakers_cents,
    # Ateliers (#208) : revenu COMPLÉMENTAIRE, identifiable séparément de la
    # production. Inclus dans four_sources_cents / baker_pool_cents seulement
    # quand ils sont effectivement répartis (taux tranché ET animateur désigné).
    :workshops,
    :total_workshop_revenue_cents,
    :total_workshop_four_sources_cents,
    :total_workshop_bakers_cents,
    :workshops_undistributed_count,
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
    # Les ateliers s'ajoutent COMME les parties : un bloc à part, qui ne touche
    # à aucun calcul de la production. Leurs parts d'artisans rejoignent en
    # revanche le même cumul, donc les mêmes partenariats.
    workshops = WorkshopRevenueService.call(period_workshops)
    artisan_totals = consolidate_artisans(days, workshops)

    Report.new(
      start_date: @start_date,
      end_date: @end_date,
      days: days,
      total_revenue_cents: sum(days, :revenue_cents),
      total_cost_price_cents: sum(days, :cost_price_cents),
      total_bread_bags_cents: sum(days, :bread_bags_cents),
      total_transport_cents: sum(days, :transport_cents),
      total_commission_cents: sum(days, :commission_cents),
      total_sales_locations_cents: sum(days, :sales_locations_cents),
      gross_margin_cents: sum(days, :gross_margin_cents) + workshops.total_four_sources_cents + workshops.total_bakers_cents,
      four_sources_cents: sum(days, :four_sources_cents) + workshops.total_four_sources_cents,
      baker_pool_cents: sum(days, :baker_pool_cents) + workshops.total_bakers_cents,
      total_party_persons: sum(days, :party_persons),
      total_party_revenue_cents: sum(days, :party_revenue_cents),
      total_party_four_sources_cents: sum(days, :party_four_sources_cents),
      total_party_bakers_cents: sum(days, :party_bakers_cents),
      total_public_party_persons: sum(days, :public_party_persons),
      total_public_party_revenue_cents: sum(days, :public_party_revenue_cents),
      total_public_party_four_sources_cents: sum(days, :public_party_four_sources_cents),
      total_public_party_bakers_cents: sum(days, :public_party_bakers_cents),
      total_historical_party_persons: sum(days, :historical_party_persons),
      total_historical_party_revenue_cents: sum(days, :historical_party_revenue_cents),
      total_historical_party_four_sources_cents: sum(days, :historical_party_four_sources_cents),
      total_historical_party_bakers_cents: sum(days, :historical_party_bakers_cents),
      workshops: workshops.workshops,
      total_workshop_revenue_cents: workshops.total_revenue_cents,
      total_workshop_four_sources_cents: workshops.total_four_sources_cents,
      total_workshop_bakers_cents: workshops.total_bakers_cents,
      workshops_undistributed_count: workshops.undistributed_count,
      artisan_totals: artisan_totals,
      artisan_settlements: build_settlements(artisan_totals),
      warnings: build_warnings(days) + orphan_party_warnings
    )
  end

  private

  # Ateliers de la période (#208), avec leurs animateurs préchargés.
  def period_workshops
    Workshop.between(@start_date, @end_date).includes(artisans: :artisan_revenue_shares).order(:held_on)
  end

  def bake_days
    BakeDay
      .accounted
      .where(baked_on: @start_date..@end_date)
      .ordered
      .includes(:baking_artisans, sales_locations: :sales_location_costs)
  end

  def build_day(bake_day)
    date = bake_day.baked_on

    revenue_cents = day_revenue_cents(bake_day)
    cost_price_cents = day_cost_price_cents(bake_day, date)
    bread_bags_cents = day_bread_bags_cents(bake_day)
    # Pas de vente ce jour-là (CA = 0) → aucun transport facturé : pas de
    # fournée, donc pas de tournée. La marge brute (et le revenu net) reste à 0.
    #
    # Le déclencheur reste le CA PROPRE de la fournée (#207) et non l'assiette
    # élargie aux parties : une pizza party se tient sur place, elle ne
    # déclenche aucune tournée. Sans cette distinction, une journée sans pain
    # mais avec une party facturerait un transport qui n'a pas eu lieu.
    transport_cents = day_own_revenue_cents(bake_day).zero? ? 0 : RevenueParameter.transport_cents_on(date)
    # Commissions Stripe des commandes EN LIGNE du jour (CA = 0 → aucune commande
    # → commission naturellement 0 : pas de paiement Stripe à déduire).
    commission_cents = day_commission_cents(date)
    # Coût des lieux de vente liés à la fournée (#150), résolu à la date de
    # cuisson. 0 si aucun lieu lié → déduction neutre, chiffres inchangés.
    sales_locations_cents = day_sales_locations_cents(bake_day, date)

    # Pizza parties (#pizza-parties) : barème spécial, HORS 70/30 — privée ET
    # publique. On isole leur CA et leur split (part 4S / part boulangers) ; le
    # coûtant des pâtons est absorbé dans ces splits. Les coûts partagés (coûtant
    # pain, sacs, transport, commissions, lieux de vente) restent sur le reste.
    party_orders = day_party_orders(bake_day)
    private_party = PizzaPartyRevenueService.call(party_orders)
    public_party = PublicPartyRevenueService.call(party_orders)
    party_sale_cents = private_party.sale_cents + public_party.sale_cents

    # Parties publiques HISTORIQUES (BilletWeb) : la recette est partie sur le
    # compte de la fondation sans passer par l'app, donc elle n'est PAS dans
    # `revenue_cents` et ne doit surtout pas être retranchée de la marge pain.
    # Seule la part boulangers, due rétroactivement, rejoint le pool.
    historical = day_historical_parties(bake_day)

    non_party_margin_cents =
      revenue_cents - party_sale_cents - cost_price_cents - bread_bags_cents -
      transport_cents - commission_cents - sales_locations_cents
    non_party_four_sources_cents = four_sources_cut(non_party_margin_cents, date)
    bread_pool_cents = non_party_margin_cents - non_party_four_sources_cents

    # Le poste « party publique » du boulanger réunit le live et l'historique :
    # pour lui, c'est la même soirée pizza, quel que soit le canal de vente.
    public_party_pool_cents = public_party.bakers_cents + historical[:bakers_cents]

    four_sources_cents = non_party_four_sources_cents + private_party.four_sources_cents +
                         public_party.four_sources_cents + historical[:four_sources_cents]
    baker_pool_cents = bread_pool_cents + private_party.bakers_cents + public_party_pool_cents
    # Marge brute totale (pain + parties) = ce qui est effectivement réparti.
    gross_margin_cents = four_sources_cents + baker_pool_cents

    artisans = bake_day.baking_artisans.to_a
    shares = artisan_shares(
      artisans,
      bread_cents: bread_pool_cents,
      private_party_cents: private_party.bakers_cents,
      public_party_cents: public_party_pool_cents,
      date: date
    )
    percent_sum = shares.sum { |share| share.percent || 0 }

    DayBreakdown.new(
      bake_day: bake_day,
      date: date,
      revenue_cents: revenue_cents,
      cost_price_cents: cost_price_cents,
      bread_bags_cents: bread_bags_cents,
      transport_cents: transport_cents,
      commission_cents: commission_cents,
      sales_locations_cents: sales_locations_cents,
      gross_margin_cents: gross_margin_cents,
      four_sources_cents: four_sources_cents,
      baker_pool_cents: baker_pool_cents,
      party_persons: private_party.persons,
      party_revenue_cents: private_party.sale_cents,
      party_four_sources_cents: private_party.four_sources_cents,
      party_bakers_cents: private_party.bakers_cents,
      public_party_persons: public_party.persons,
      public_party_revenue_cents: public_party.sale_cents,
      public_party_four_sources_cents: public_party.four_sources_cents,
      public_party_bakers_cents: public_party.bakers_cents,
      historical_party_persons: historical[:persons],
      historical_party_revenue_cents: historical[:sale_cents],
      historical_party_four_sources_cents: historical[:four_sources_cents],
      historical_party_bakers_cents: historical[:bakers_cents],
      bread_pool_cents: bread_pool_cents,
      private_party_pool_cents: private_party.bakers_cents,
      public_party_pool_cents: public_party_pool_cents,
      artisan_shares: shares,
      percent_sum: percent_sum,
      percent_overflow: percent_sum > 100
    )
  end

  # Assiette comptable du jour (#207) : les commandes finalisées RATTACHÉES à la
  # fournée, PLUS les commandes party que cette fournée prépare et qui, elles,
  # n'ont pas de fournée (`bake_day: nil` par design).
  #
  # Les deux ensembles sont fusionnés puis dédupliqués par id : une commande qui
  # porterait à la fois une fournée et un événement n'est comptée qu'une fois.
  # `PartyEvent.prepared_by` garantit par ailleurs qu'une party n'est rattachée
  # qu'à UNE fournée, donc aucun double comptage entre deux jours.
  def day_accounted_orders(bake_day)
    @day_accounted_orders ||= {}
    @day_accounted_orders[bake_day.id] ||= begin
      direct = bake_day.orders.completed
                       .includes(:bake_day, order_items: { product_variant: [ :variant_cost_prices, :product ] })
                       .to_a
      via_event = BakeDayPartyOrders.completed(bake_day)

      (direct + via_event).uniq(&:id)
    end
  end

  # Commandes finalisées du jour, préchargées pour le barème party
  # (PizzaPartyRevenueService itère les articles + le coûtant historisé).
  def day_party_orders(bake_day)
    day_accounted_orders(bake_day)
  end

  # CA des commandes RATTACHÉES à la fournée, hors parties venues par
  # l'événement. Sert uniquement au déclenchement du transport (cf. build_day).
  def day_own_revenue_cents(bake_day)
    bake_day.orders.completed.sum(:total_cents)
  end

  # CA du jour. Il DOIT porter sur la même assiette que `day_party_orders` :
  # le CA party en est retranché pour isoler la marge « pain » (cf. build_day).
  # Compter une party dans le split sans la compter dans le CA creuserait un
  # trou du même montant dans la marge non-party.
  def day_revenue_cents(bake_day)
    day_accounted_orders(bake_day).sum(&:total_cents)
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

  # Coût des lieux de vente liés à la fournée (#150), résolu à `date` (la date de
  # cuisson). Chaque lieu contribue le coût de la période qui couvre ce jour, ou
  # 0 s'il n'en a aucune. Aucune fournée liée → 0 (déduction neutre).
  def day_sales_locations_cents(bake_day, date)
    bake_day.sales_locations_cost_cents(on: date)
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

  # Parties publiques HISTORIQUES (BilletWeb) que cette fournée prépare, agrégées.
  # Même règle de rattachement que les parties publiques vendues sur le site :
  # les boulangers de la fournée qui a pétri les pâtons touchent la part due.
  def day_historical_parties(bake_day)
    events = PartyEvent.public_prepared_by(bake_day).historical.to_a
    blank = { persons: 0, sale_cents: 0, four_sources_cents: 0, bakers_cents: 0, events: [] }
    return blank if events.empty?

    events.each_with_object(blank.dup) do |event, acc|
      result = HistoricalPartyRevenueService.call(event)
      acc[:persons] += result.persons
      acc[:sale_cents] += result.sale_cents
      acc[:four_sources_cents] += result.four_sources_cents
      acc[:bakers_cents] += result.bakers_cents
      acc[:events] = acc[:events] + [ event ]
    end
  end

  # Répartition du pool entre les artisans présents, au % littéral configuré.
  # Chaque poste est réparti pour lui-même : additionner ensuite est exact,
  # alors que ventiler un total arrondi ne l'aurait pas été.
  def artisan_shares(artisans, bread_cents:, private_party_cents:, public_party_cents:, date:)
    artisans.map do |artisan|
      percent = artisan.revenue_share_percent(on: date)
      cut = ->(pool) { percent.nil? ? 0 : (pool * percent / 100.0).round }

      bread = cut.call(bread_cents)
      private_party = cut.call(private_party_cents)
      public_party = cut.call(public_party_cents)

      ArtisanShare.new(
        artisan: artisan,
        percent: percent,
        bread_cents: bread,
        private_party_cents: private_party,
        public_party_cents: public_party,
        amount_cents: bread + private_party + public_party
      )
    end
  end

  # Cumul par artisan sur l'ensemble des jours (additionnable par mois côté
  # appelant en filtrant la période). Trié par nom pour un affichage stable.
  def consolidate_artisans(days, workshops = nil)
    grouped = Hash.new do |hash, key|
      hash[key] = { artisan: nil, amount_cents: 0, bread_cents: 0, private_party_cents: 0,
                    public_party_cents: 0, workshop_cents: 0, days_count: 0 }
    end

    days.each do |day|
      day.artisan_shares.each do |share|
        bucket = grouped[share.artisan.id]
        bucket[:artisan] = share.artisan
        bucket[:amount_cents] += share.amount_cents
        bucket[:bread_cents] += share.bread_cents
        bucket[:private_party_cents] += share.private_party_cents
        bucket[:public_party_cents] += share.public_party_cents
        bucket[:days_count] += 1
      end
    end

    # Les parts d'atelier (#208) rejoignent le MÊME cumul : c'est ce qui leur
    # fait traverser la couche partenariat sans une ligne de code de plus.
    # `days_count` compte les jours de production : un atelier n'en est pas un,
    # il ne l'incrémente pas.
    workshops&.workshops&.each do |workshop|
      workshop.artisan_shares.each do |share|
        bucket = grouped[share.artisan.id]
        bucket[:artisan] = share.artisan
        bucket[:amount_cents] += share.amount_cents
        bucket[:workshop_cents] += share.amount_cents
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

      weights = memberships.map(&:weight)
      # Poste par poste : mettre en commun le total puis le ventiler au prorata
      # ferait dériver les colonnes de quelques centimes par rapport au total.
      shares_by_bucket = BUCKETS.index_with do |bucket|
        pooled = memberships.sum { |ms| raw_by_id[ms.artisan_id]&.public_send(bucket) || 0 }
        distribute(pooled, weights)
      end

      memberships.each_with_index do |ms, index|
        raw = raw_by_id[ms.artisan_id]
        buckets = BUCKETS.index_with { |bucket| shares_by_bucket[bucket][index] }

        settlements << ArtisanSettlement.new(
          artisan: ms.artisan,
          partnership: partnership,
          raw_cents: raw&.amount_cents || 0,
          settled_cents: buckets.values.sum,
          days_count: raw&.days_count || 0,
          **buckets
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
        days_count: total.days_count,
        **BUCKETS.index_with { |bucket| total.public_send(bucket) }
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
    end + undistributed_warnings(days)
  end

  # L'inverse de l'excès : du pool qui ne trouve personne. Aucun boulanger affecté
  # à la fournée, ou des parts qui ne font pas 100 % — dans les deux cas l'argent
  # reste dans le total du pool mais n'est versé à personne, et rien ne le disait.
  def undistributed_warnings(days)
    days.filter_map do |day|
      next if day.baker_pool_cents <= 0

      distributed = day.artisan_shares.sum(&:amount_cents)
      leftover = day.baker_pool_cents - distributed
      next if leftover <= 0

      reason =
        if day.artisan_shares.empty?
          "aucun boulanger n'est affecté à cette fournée"
        else
          "la somme des parts des boulangers présents n'atteint que #{format_percent(day.percent_sum)} %"
        end

      "Le #{I18n.l(day.date)}, #{format_currency(leftover)} du pool ne sont versés à personne : #{reason}."
    end
  end

  def format_currency(cents)
    format("%.2f €", cents / 100.0).tr(".", ",")
  end

  # Une party publique tenue avant toute fournée n'est rattachée à aucune : son
  # argent sortirait du rapport sans un mot. On le dit plutôt que de le perdre.
  def orphan_party_warnings
    first_bake_day = BakeDay.accounted.minimum(:baked_on)
    return [] if first_bake_day.blank?

    PartyEvent.public_events.not_deleted
              .where(held_on: @start_date..@end_date)
              .where(held_on: ...first_bake_day)
              .order(:held_on)
              .map do |event|
      "La pizza party publique du #{I18n.l(event.held_on)} précède toute fournée " \
        "comptabilisée : elle n'est rattachée à aucun jour de production, et son " \
        "revenu n'entre pas dans le pool des boulangers."
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
