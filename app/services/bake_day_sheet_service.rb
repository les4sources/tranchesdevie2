# frozen_string_literal: true

# Feuille compta d'un JOUR DE CUISSON (#feuille-compta).
#
# Reproduit la feuille Google Sheet de Stéphanie — une ligne par variante (format)
# vendue le jour, avec quantité (« Commandes ») et CA net — MAIS avec le calcul
# AUTHORITATIVE de l'app (`BakerRevenueService`) : la part boulangers / 4 Sources
# est le split 70/30 de la marge du jour APRÈS déduction des coûts partagés (coûtant
# pain, sacs, transport, commissions Stripe, lieux de vente), et les pizza parties
# suivent leur barème spécial (hors 70/30).
#
# But : permettre à Stéphanie de valider ses chiffres au même format, en voyant
# explicitement les déductions que sa feuille omet.
#
# INVARIANT CENTRAL (#274) : le total du tableau égale EXACTEMENT le CA du jour
# affiché par la carte « CA total » (`day.revenue_cents`). C'est structurel, pas
# une coïncidence : les lignes sont construites à partir de la MÊME assiette de
# commandes que `BakerRevenueService` — les commandes rattachées à la fournée
# PLUS les commandes party que cette fournée prépare (`bake_day: nil` par
# design). Le tableau se nourrissait auparavant d'une requête datée qui joignait
# `bake_days` : toute pizza party en sortait, sans que rien n'explique l'écart.
#
# Usage : BakeDaySheetService.call(bake_day)  # => Result
class BakeDaySheetService
  # Une ligne produit/format vendu le jour.
  Row = Struct.new(
    :variant,
    :label,             # « Pain froment – 1 kg »
    :kind,              # :bread ou :party
    :unit_price_cents,  # prix classique (variante)
    :unit_cost_cents,   # coûtant unitaire à la date
    :qty,               # « Commandes » (quantité vendue)
    :gross_cents,       # CA AVANT remise (Σ qty × prix unitaire)
    :sale_cents,        # CA net de la ligne (après remise)
    keyword_init: true
  ) do
    def cost_cents
      unit_cost_cents * qty
    end

    def party?
      kind == :party
    end

    # Remise du format = CA brut − CA net (≥ 0).
    def discount_cents
      gross_cents - sale_cents
    end

    def discount_percent
      return 0.0 if gross_cents.zero?

      (discount_cents * 100.0 / gross_cents).round(1)
    end
  end

  # Ventilation du CA du jour par moyen de paiement RÉELLEMENT enregistré
  # (#274). Volontairement construite sur `Order#payment_method` (présence d'un
  # Payment Stripe ou d'une transaction de portefeuille) et non sur
  # `payment_status`, qui n'est pas fiable : 556 commandes au statut logistique
  # avancé y portent « unpaid » sans qu'on sache ce qui a été encaissé en
  # liquide. La ligne `untracked_cents` rapporte donc un fait — « aucun paiement
  # enregistré » — et surtout PAS un impayé.
  Settlement = Struct.new(:stripe_cents, :wallet_cents, :untracked_cents, keyword_init: true) do
    def total_cents
      stripe_cents + wallet_cents + untracked_cents
    end
  end

  Result = Struct.new(:bake_day, :date, :rows, :day, :settlement, keyword_init: true) do
    def bread_rows
      rows.reject(&:party?)
    end

    def party_rows
      rows.select(&:party?)
    end

    # Σ CA des lignes — égale le CA du jour (day.revenue_cents) par construction.
    def total_sale_cents
      rows.sum(&:sale_cents)
    end

    def total_gross_cents
      rows.sum(&:gross_cents)
    end

    def total_discount_cents
      rows.sum(&:discount_cents)
    end

    def total_cost_cents
      rows.sum(&:cost_cents)
    end

    def bread_sale_cents
      bread_rows.sum(&:sale_cents)
    end

    def party_sale_cents
      party_rows.sum(&:sale_cents)
    end

    # Le tableau se réconcilie-t-il avec la carte « CA total » ? Doit toujours
    # être vrai ; exposé pour que la vue puisse le signaler plutôt que de
    # laisser un écart muet à l'écran.
    def reconciled?
      day.nil? || total_sale_cents == day.revenue_cents
    end
  end

  def self.call(bake_day)
    new(bake_day).call
  end

  def initialize(bake_day)
    @bake_day = bake_day
    @date = bake_day.baked_on
  end

  def call
    Result.new(
      bake_day: @bake_day,
      date: @date,
      rows: build_rows,
      day: day_breakdown,
      settlement: build_settlement
    )
  end

  private

  # Assiette comptable du jour — la même que `BakerRevenueService` : commandes
  # finalisées rattachées à la fournée, plus les commandes party que cette
  # fournée prépare. Dédupliquée par id, pour une commande qui porterait à la
  # fois une fournée et un événement.
  #
  # Un brouillon (#197) n'est comptabilisé nulle part : sa feuille reste vide.
  def accounted_orders
    @accounted_orders ||=
      if @bake_day.draft?
        []
      else
        direct = @bake_day.orders.completed
                          .includes(order_items: { product_variant: [ :variant_cost_prices, :product ] })
                          .to_a
        (direct + BakeDayPartyOrders.completed(@bake_day)).uniq(&:id)
      end
  end

  # Une ligne par variante vendue le jour (CA net réconcilié), pains d'abord puis
  # parties, chaque groupe trié par CA décroissant.
  def build_rows
    acc = Hash.new do |hash, key|
      hash[key] = { variant: nil, kind: :bread, qty: 0, gross_cents: 0, sale_cents: 0 }
    end

    accounted_orders.each do |order|
      net_by_item = Order.net_cents_by_item(order)

      order.order_items.each do |item|
        variant = item.product_variant
        next if variant.nil?

        bucket = acc[variant.id]
        bucket[:variant] = variant
        bucket[:kind] = :party if party_variant?(variant)
        bucket[:qty] += item.qty
        bucket[:gross_cents] += item.qty * item.unit_price_cents
        bucket[:sale_cents] += net_by_item.fetch(item.id, 0)
      end
    end

    acc.values
       .map { |entry| build_row(entry) }
       .sort_by { |row| [ row.party? ? 1 : 0, -row.sale_cents ] }
  end

  def build_row(entry)
    variant = entry[:variant]
    Row.new(
      variant: variant,
      label: [ variant.product.name, variant.name ].compact.map(&:to_s).reject(&:empty?).join(" – "),
      kind: entry[:kind],
      unit_price_cents: variant.price_cents,
      unit_cost_cents: variant.cost_price_cents(on: @date) || 0,
      qty: entry[:qty],
      gross_cents: entry[:gross_cents],
      sale_cents: entry[:sale_cents]
    )
  end

  # Pâtons, forfait et places de party publique : tout ce qui porte un rôle
  # pizza party. Le reste est du pain (ou de la revente).
  def party_variant?(variant)
    !variant.product.pizza_party_role_none?
  end

  # Ventilation du CA du jour par moyen de paiement réellement enregistré.
  def build_settlement
    totals = { stripe: 0, wallet: 0, untracked: 0 }

    accounted_orders.each do |order|
      bucket = order.payment_method || :untracked
      totals[bucket] += order.total_cents.to_i
    end

    Settlement.new(
      stripe_cents: totals[:stripe],
      wallet_cents: totals[:wallet],
      untracked_cents: totals[:untracked]
    )
  end

  # Détail authoritative du jour (marge, déductions, split 70/30, parties) —
  # réutilise le moteur de référence. Une seule journée dans la période.
  def day_breakdown
    BakerRevenueService.new(start_date: @date, end_date: @date).call.days.first
  end
end
