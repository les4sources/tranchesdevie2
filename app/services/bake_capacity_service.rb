# frozen_string_literal: true

class BakeCapacityService
  attr_reader :bake_day

  def initialize(bake_day)
    @bake_day = bake_day
  end

  # Returns detailed usage per resource
  def usage
    @usage ||= {
      molds: mold_usage,
      kneader: kneader_usage,
      oven: oven_usage
    }
  end

  # Returns the fill percentage of the most constrained resource (0..100+)
  def fill_percentage
    percentages = []

    usage[:molds].each do |entry|
      percentages << (entry[:used].to_f / entry[:limit] * 100).round if entry[:limit] > 0
    end

    usage[:kneader].each do |entry|
      percentages << (entry[:used].to_f / entry[:limit] * 100).round if entry[:limit] > 0
    end

    oven = usage[:oven]
    percentages << (oven[:used].to_f / oven[:limit] * 100).round if oven[:limit] > 0

    percentages.max || 0
  end

  # True if any resource is at or above 100%
  def fully_booked?
    fill_percentage >= 100
  end

  # Check if adding cart_items would exceed capacity
  # cart_items: array of { variant_id:, qty: } or objects responding to product_variant_id and qty
  def cart_fits?(cart_items)
    errors = []
    additional = compute_additional(cart_items)

    # Check molds
    mold_usage.each do |entry|
      extra = additional[:molds][entry[:mold_type].id] || 0
      if entry[:used] + extra > entry[:limit]
        errors << "Moules #{entry[:mold_type].name} : capacité dépassée (#{entry[:used] + extra}/#{entry[:limit]})"
      end
    end

    # Check kneader
    kneader_usage.each do |entry|
      extra = additional[:kneader][entry[:flour].id] || 0
      if entry[:used] + extra > entry[:limit]
        errors << "Pétrin #{entry[:flour].name} : capacité dépassée"
      end
    end

    # Check oven
    oven = oven_usage
    extra_oven = additional[:oven]
    if oven[:used] + extra_oven > oven[:limit]
      errors << "Four : capacité dépassée"
    end

    { fits: errors.empty?, errors: errors }
  end

  private

  # All breads order_items for this bake_day (excluding cancelled)
  def breads_order_items
    @breads_order_items ||= OrderItem
      .joins(order: [], product_variant: :product)
      .where(orders: { bake_day_id: bake_day.id })
      .where.not(orders: { status: :cancelled })
      .where(products: { category: :breads })
      .includes(product_variant: { product: { product_flours: :flour } })
      .to_a
  end

  def mold_usage
    @mold_usage ||= begin
      # Count units per mold_type_id
      counts = Hash.new(0)
      breads_order_items.each do |item|
        mt_id = item.product_variant.mold_type_id
        counts[mt_id] += item.qty if mt_id
      end

      MoldType.not_deleted.ordered.map do |mt|
        { mold_type: mt, used: counts[mt.id], limit: mt.limit }
      end
    end
  end

  def kneader_usage
    @kneader_usage ||= begin
      # Compute dough grams per flour
      flour_grams = Hash.new(0.0)

      breads_order_items.each do |item|
        variant = item.product_variant
        dough_grams = item.qty * (variant.flour_quantity || 0)
        next if dough_grams.zero?

        variant.product.product_flours.each do |pf|
          flour_grams[pf.flour_id] += dough_grams * pf.percentage / 100.0
        end
      end

      Flour.not_deleted.ordered.select { |f| f.kneader_limit_grams.present? }.map do |flour|
        { flour: flour, used: flour_grams[flour.id].round, limit: flour.kneader_limit_grams }
      end
    end
  end

  def oven_usage
    @oven_usage ||= begin
      total_grams = breads_order_items.sum do |item|
        item.qty * (item.product_variant.flour_quantity || 0)
      end

      { used: total_grams, limit: bake_day.oven_capacity_grams }
    end
  end

  def compute_additional(cart_items)
    molds = Hash.new(0)
    kneader = Hash.new(0.0)
    oven_total = 0

    cart_items.each do |ci|
      variant_id = if ci.respond_to?(:product_variant_id)
                     ci.product_variant_id
                   elsif ci.is_a?(Hash)
                     ci["product_variant_id"] || ci[:product_variant_id] || ci["variant_id"] || ci[:variant_id]
                   end

      variant = if ci.respond_to?(:product_variant)
                  ci.product_variant
                else
                  ProductVariant.includes(product: { product_flours: :flour }).find(variant_id)
                end

      qty = ci.respond_to?(:qty) ? ci.qty : (ci["qty"] || ci[:qty]).to_i
      next unless variant.product.breads?

      # Molds
      molds[variant.mold_type_id] += qty if variant.mold_type_id

      # Dough
      dough_grams = qty * (variant.flour_quantity || 0)
      next if dough_grams.zero?

      oven_total += dough_grams

      variant.product.product_flours.each do |pf|
        kneader[pf.flour_id] += dough_grams * pf.percentage / 100.0
      end
    end

    { molds: molds, kneader: kneader.transform_values(&:round), oven: oven_total }
  end
end
