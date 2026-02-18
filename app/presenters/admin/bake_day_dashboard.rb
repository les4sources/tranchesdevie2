module Admin
  class BakeDayDashboard
    XXL_MOLD_PATTERNS = [
      /xxl/i
    ].freeze

    LARGE_MOLD_PATTERNS = [
      /1\s?kg/i,
      /1000/,
      /grand/i
    ].freeze

    MIDDLE_MOLD_PATTERNS = [
      /800\s?g/i,
      /0\.8/i,
      /800/,
      /moyen/i
    ].freeze

    SMALL_MOLD_PATTERNS = [
      /600\s?g/i,
      /0\.6/i,
      /600/,
      /petit/i
    ].freeze

    attr_reader :bake_day

    def initialize(bake_day)
      @bake_day = bake_day
    end

    def orders
      @orders ||= bake_day.orders
                           .includes(:customer,
                                     order_items: {
                                       product_variant: [
                                         { product: { product_images: { image_attachment: :blob }, product_flours: :flour } },
                                         { product_images: { image_attachment: :blob } }
                                       ]
                                     })
                           .order(:created_at)
    end

    def order_items
      @order_items ||= orders.flat_map(&:order_items)
    end

    def variant_stats
      @variant_stats ||= begin
        grouped = order_items.group_by(&:product_variant)

        grouped.map do |variant, items|
          product = variant.product
          order_ids = items.map { |item| item.order_id }.compact.uniq
          {
            variant: variant,
            product: product,
            category: product.category,
            orders_count: order_ids.size,
            units_count: items.sum(&:qty),
            mold_size: detect_mold_size(product, variant)
          }
        end.sort_by { |stat| [stat[:product].name.downcase, stat[:variant].name.downcase] }
      end
    end

    def breads_mold_requirements
      stats = variant_stats.select { |stat| stat[:product].breads? }

      {
        xxl: stats.select { |stat| stat[:mold_size] == :xxl }.sum { |stat| stat[:units_count] },
        large: stats.select { |stat| stat[:mold_size] == :large }.sum { |stat| stat[:units_count] },
        middle: stats.select { |stat| stat[:mold_size] == :middle }.sum { |stat| stat[:units_count] },
        small: stats.select { |stat| stat[:mold_size] == :small }.sum { |stat| stat[:units_count] },
        unspecified: stats.select { |stat| stat[:mold_size].nil? }.sum { |stat| stat[:units_count] }
      }
    end

    def kpis
      total_cents = orders.sum(&:total_cents)

      {
        orders_count: orders.size,
        items_count: order_items.sum(&:qty),
        revenue_cents: total_cents,
        variants_count: variant_stats.size,
        open_orders: orders.count { |order| order.unpaid? },
        ready_orders: orders.count { |order| order.ready? || order.picked_up? }
      }
    end

    def customer_breakdown
      @customer_breakdown ||= orders.group_by(&:customer).map do |customer, customer_orders|
        {
          customer: customer,
          orders: customer_orders.map do |order|
            {
              order: order,
              items: order.order_items.map do |item|
                {
                  variant: item.product_variant,
                  qty: item.qty
                }
              end
            }
          end,
          total_cents: customer_orders.sum(&:total_cents),
          statuses: customer_orders.group_by(&:status).transform_values(&:count)
        }
      end.sort_by { |entry| [entry[:customer].last_name.to_s.downcase, entry[:customer].first_name.to_s.downcase] }
    end

    def status_distribution
      orders.group_by(&:status).transform_values(&:count)
    end

    def unpaid_orders?
      orders.any?(&:unpaid?)
    end

    def total_flour_quantity
      confirmed_orders = orders.select { |order| order.unpaid? || order.paid? || order.ready? || order.picked_up? }
      confirmed_order_items = confirmed_orders.flat_map(&:order_items)

      confirmed_order_items.sum do |item|
        flour_qty = item.product_variant.flour_quantity || 0
        item.qty * flour_qty
      end
    end

    def product_flour_stats
      @product_flour_stats ||= begin
        confirmed_orders = orders.select { |order| order.unpaid? || order.paid? || order.ready? || order.picked_up? }
        confirmed_order_items = confirmed_orders.flat_map(&:order_items)

        # Group by product_id to ensure proper grouping
        grouped_by_product_id = confirmed_order_items.group_by { |item| item.product_variant.product_id }

        grouped_by_product_id.map do |product_id, items|
          # Get the product from the first item (all items in this group have the same product)
          product = items.first.product_variant.product
          
          total_flour = items.sum do |item|
            flour_qty = item.product_variant.flour_quantity || 0
            item.qty * flour_qty
          end

          {
            product: product,
            flour_quantity: total_flour
          }
        end.select { |stat| stat[:flour_quantity].positive? }
           .sort_by { |stat| stat[:product].name.downcase }
      end
    end

    def flour_type_stats
      @flour_type_stats ||= begin
        confirmed_orders = orders.select { |order| order.unpaid? || order.paid? || order.ready? || order.picked_up? }
        confirmed_order_items = confirmed_orders.flat_map(&:order_items)

        # Build hash: flour_id => { flour: Flour, total: 0, by_product: { product => quantity } }
        flour_stats = Hash.new { |h, flour_id| h[flour_id] = { flour: nil, total: 0.0, by_product: Hash.new(0) } }

        confirmed_order_items.each do |item|
          variant = item.product_variant
          product = variant.product
          total_dough = item.qty * (variant.flour_quantity || 0)
          next if total_dough.zero?

          product.product_flours.includes(:flour).each do |pf|
            flour = pf.flour
            contribution = total_dough * pf.percentage / 100.0
            flour_stats[flour.id][:flour] = flour
            flour_stats[flour.id][:total] += contribution
            flour_stats[flour.id][:by_product][product] += contribution
          end
        end

        flour_stats.values
          .select { |stat| stat[:flour].present? && stat[:total].positive? }
          .map do |stat|
            product_details = stat[:by_product].map do |product, qty|
              { product: product, flour_quantity: qty.round }
            end.select { |detail| detail[:flour_quantity].positive? }
               .sort_by { |detail| detail[:product].name.downcase }

            {
              flour: stat[:flour],
              flour_quantity: stat[:total].round,
              products: product_details
            }
          end
          .sort_by { |stat| [stat[:flour].position || Float::INFINITY, stat[:flour].name.downcase] }
      end
    end

    def dough_quantities
      @dough_quantities ||= begin
        ratios = DoughRatio.ratios_hash
        farine_ratio = ratios["farine"] || 0.5556
        sel_ratio    = ratios["sel"]    || 0.022
        eau_ratio    = ratios["eau"]    || 0.655
        levain_ratio = ratios["levain"] || 0.12095

        per_flour = flour_type_stats.map do |stat|
          pate_grams = stat[:flour_quantity].to_f
          farine_grams = farine_ratio * pate_grams

          {
            flour: stat[:flour],
            pate_kg:   (pate_grams / 1000.0).round(2),
            farine_kg: (farine_grams / 1000.0).round(2),
            sel_kg:    (farine_grams * sel_ratio / 1000.0).round(3),
            eau_l:     (farine_grams * eau_ratio / 1000.0).round(2),
            levain_kg: (levain_ratio * pate_grams / 1000.0).round(3)
          }
        end

        totals = {
          pate_kg:   per_flour.sum { |f| f[:pate_kg] }.round(2),
          farine_kg: per_flour.sum { |f| f[:farine_kg] }.round(2),
          sel_kg:    per_flour.sum { |f| f[:sel_kg] }.round(3),
          eau_l:     per_flour.sum { |f| f[:eau_l] }.round(2),
          levain_kg: per_flour.sum { |f| f[:levain_kg] }.round(3)
        }

        { per_flour: per_flour, totals: totals }
      end
    end

    def ingredient_stats
      @ingredient_stats ||= begin
        confirmed_orders = orders.select { |order| order.unpaid? || order.paid? || order.ready? || order.picked_up? }
        confirmed_order_items = confirmed_orders.flat_map(&:order_items)

        ingredient_totals = Hash.new { |h, k| h[k] = { ingredient: nil, total: BigDecimal("0") } }

        confirmed_order_items.each do |item|
          variant = item.product_variant
          variant.variant_ingredients.includes(:ingredient).each do |vi|
            ingredient = vi.ingredient
            ingredient_totals[ingredient.id][:ingredient] = ingredient
            ingredient_totals[ingredient.id][:total] += vi.quantity * item.qty
          end
        end

        ingredient_totals.values
          .select { |stat| stat[:total].positive? }
          .sort_by { |stat| stat[:ingredient].name.downcase }
      end
    end

    private

    def detect_mold_size(product, variant)
      label = "#{product.name} #{variant.name}".downcase

      return :xxl if XXL_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }
      return :large if LARGE_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }
      return :middle if MIDDLE_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }
      return :small if SMALL_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }

      nil
    end
  end
end


