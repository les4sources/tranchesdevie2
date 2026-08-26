# frozen_string_literal: true

# Coût des matières premières sur une période, calculé à partir des prix au kilo
# HISTORISÉS (#209).
#
# Le point qui compte : chaque quantité est valorisée au prix en vigueur À LA
# DATE DE SA FOURNÉE, pas au prix d'aujourd'hui. C'est ce qui fait qu'un
# changement de prix ne modifie aucun chiffre déjà produit — « le reporting ne
# devrait jamais changer ».
#
# Un élément sans prix à la date n'est PAS compté pour zéro : sa quantité est
# affichée, son coût est `nil`, et il est signalé comme non valorisé. Un total
# faussement rassurant serait pire qu'un trou visible.
class IngredientCostReportService
  Line = Struct.new(:subject, :kind, :grams, :cost_cents, :missing_price_grams, keyword_init: true) do
    def kilos = (grams / 1000.0).round(3)
    def priced? = !cost_cents.nil?
    def partially_priced? = missing_price_grams.positive?
    def cost_euros = cost_cents.nil? ? nil : (cost_cents / 100.0).round(2)
  end

  Result = Struct.new(:ingredient_lines, :flour_lines, :total_cost_cents, :unpriced_count, keyword_init: true) do
    def total_cost_euros = (total_cost_cents / 100.0).round(2)
    def lines = ingredient_lines + flour_lines
  end

  def self.call(start_date:, end_date:)
    new(start_date: start_date, end_date: end_date).call
  end

  def initialize(start_date:, end_date:)
    @start_date = start_date
    @end_date = end_date
  end

  def call
    ingredient_lines = build_lines(ingredient_usage, :ingredient)
    flour_lines = build_lines(flour_usage, :flour)
    lines = ingredient_lines + flour_lines

    Result.new(
      ingredient_lines: ingredient_lines,
      flour_lines: flour_lines,
      total_cost_cents: lines.filter_map(&:cost_cents).sum,
      unpriced_count: lines.count { |line| line.partially_priced? }
    )
  end

  private

  # Commandes finalisées de la période, avec leur date de fournée : c'est cette
  # date qui sert à résoudre le prix.
  def completed_items
    @completed_items ||= OrderItem
      .joins(order: :bake_day)
      .where(orders: { id: Order.completed.select(:id) })
      .where(bake_days: { baked_on: @start_date..@end_date })
      .includes(product_variant: [ { variant_ingredients: :ingredient }, { product: { product_flours: :flour } } ])
      .select("order_items.*, bake_days.baked_on AS bake_date")
      .to_a
  end

  # Grammes d'ingrédient consommés, ventilés par (ingrédient, date de fournée).
  def ingredient_usage
    usage = Hash.new { |hash, key| hash[key] = Hash.new(0.0) }

    completed_items.each do |item|
      date = item.bake_date
      item.product_variant.variant_ingredients.each do |vi|
        next unless vi.ingredient.weight?

        usage[vi.ingredient][date] += vi.quantity.to_f * item.qty
      end
    end

    usage
  end

  # Grammes de farine consommés — la pâte ventilée selon les pourcentages du
  # produit, comme le fait déjà le tableau de panification.
  def flour_usage
    usage = Hash.new { |hash, key| hash[key] = Hash.new(0.0) }

    completed_items.each do |item|
      date = item.bake_date
      variant = item.product_variant
      dough = item.qty * (variant.flour_quantity || 0)
      next if dough.zero?

      variant.product.product_flours.each do |pf|
        usage[pf.flour][date] += dough * pf.percentage / 100.0
      end
    end

    usage
  end

  def build_lines(usage, kind)
    usage.map do |subject, by_date|
      grams = by_date.values.sum
      cost_cents = 0.0
      missing_grams = 0.0
      any_priced = false

      by_date.each do |date, day_grams|
        price = subject.price_per_kg_cents_on(date)

        if price.nil?
          missing_grams += day_grams
        else
          any_priced = true
          cost_cents += day_grams / 1000.0 * price
        end
      end

      Line.new(
        subject: subject,
        kind: kind,
        grams: grams.round,
        cost_cents: any_priced ? cost_cents.round : nil,
        missing_price_grams: missing_grams.round
      )
    end.sort_by { |line| line.subject.name.downcase }
  end
end
