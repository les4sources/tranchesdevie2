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
# Usage : BakeDaySheetService.call(bake_day)  # => Result
class BakeDaySheetService
  # Une ligne produit/format vendu le jour.
  Row = Struct.new(
    :variant,
    :label,             # « Pain froment – 1 kg »
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

    # Remise du format = CA brut − CA net (≥ 0).
    def discount_cents
      gross_cents - sale_cents
    end

    def discount_percent
      return 0.0 if gross_cents.zero?

      (discount_cents * 100.0 / gross_cents).round(1)
    end
  end

  Result = Struct.new(:bake_day, :date, :rows, :day, keyword_init: true) do
    # Σ CA des lignes — se réconcilie avec le CA du jour (day.revenue_cents).
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
      day: day_breakdown
    )
  end

  private

  # Une ligne par variante vendue le jour (CA net réconcilié), triée par CA décroissant.
  def build_rows
    Order.sales_by_variant_between(@date, @date).map do |entry|
      variant = entry[:variant]
      Row.new(
        variant: variant,
        label: [ variant.product.name, variant.name ].compact.map(&:to_s).reject(&:empty?).join(" – "),
        unit_price_cents: variant.price_cents,
        unit_cost_cents: variant.cost_price_cents(on: @date) || 0,
        qty: entry[:total_quantity],
        gross_cents: entry[:total_gross_cents],
        sale_cents: entry[:total_cents]
      )
    end
  end

  # Détail authoritative du jour (marge, déductions, split 70/30, parties) —
  # réutilise le moteur de référence. Une seule journée dans la période.
  def day_breakdown
    BakerRevenueService.new(start_date: @date, end_date: @date).call.days.first
  end
end
