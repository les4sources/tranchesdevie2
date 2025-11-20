module Admin
  class BakeDayDashboard
    LARGE_MOLD_PATTERNS = [
      /1\s?kg/i,
      /1000/,
      /grand/i
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
      confirmed_orders = orders.select { |order| order.paid? || order.ready? || order.picked_up? }
      confirmed_order_items = confirmed_orders.flat_map(&:order_items)

      confirmed_order_items.sum do |item|
        flour_qty = item.product_variant.flour_quantity || 0
        item.qty * flour_qty
      end
    end

    private

    def detect_mold_size(product, variant)
      label = "#{product.name} #{variant.name}".downcase

      return :large if LARGE_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }
      return :small if SMALL_MOLD_PATTERNS.any? { |pattern| label.match?(pattern) }

      nil
    end
  end
end


