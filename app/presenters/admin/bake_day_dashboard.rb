module Admin
  class BakeDayDashboard
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
                                         { product: { product_images: { image_attachment: :blob } } },
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
        large: stats.select { |stat| stat[:mold_size] == :large }.sum { |stat| stat[:units_count] },
        middle: stats.select { |stat| stat[:mold_size] == :middle }.sum { |stat| stat[units_count] },
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
        open_orders: orders.count { |order| order.pending? || order.unpaid? },
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

        # Group by flour type
        grouped_by_flour = confirmed_order_items.group_by do |item|
          item.product_variant.product.flour.presence || "none"
        end

        grouped_by_flour.map do |flour_type, items|
          # Group items by product to get product-level stats
          grouped_by_product = items.group_by { |item| item.product_variant.product_id }
          
          product_details = grouped_by_product.map do |product_id, product_items|
            product = product_items.first.product_variant.product
            product_flour = product_items.sum do |item|
              flour_qty = item.product_variant.flour_quantity || 0
              item.qty * flour_qty
            end
            
            {
              product: product,
              flour_quantity: product_flour
            }
          end.select { |detail| detail[:flour_quantity].positive? }
             .sort_by { |detail| detail[:product].name.downcase }
          
          total_flour = product_details.sum { |detail| detail[:flour_quantity] }

          {
            flour_type: flour_type,
            flour_quantity: total_flour,
            products: product_details
          }
        end.select { |stat| stat[:flour_quantity].positive? }
           .sort_by { |stat| stat[:flour_type] }
      end
    end

    private

    def detect_mold_size(product, variant)
      label = "#{product.name} #{variant.name}".downcase

      return :large if LARGE_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }
      return :middle if MIDDLE_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }
      return :small if SMALL_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }

      nil
    end
  end
end


