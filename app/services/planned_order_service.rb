class PlannedOrderService
  class << self
    def upsert(customer:, bake_day:, items:)
      return { error: "Cut-off dépassé" } if bake_day.cut_off_passed?
      return { error: "Aucun produit sélectionné" } if items.blank?

      order = customer.orders.find_or_initialize_by(
        bake_day: bake_day,
        status: :planned,
        source: :calendar
      )

      Order.transaction do
        order.order_items.destroy_all if order.persisted?

        items.each do |item|
          variant = ProductVariant.find(item[:product_variant_id])
          order.order_items.build(
            product_variant_id: variant.id,
            qty: item[:qty],
            unit_price_cents: variant.price_cents
          )
        end

        order.total_cents = order.order_items.sum { |i| i.qty * i.unit_price_cents }
        order.save!
      end

      { order: order }
    rescue ActiveRecord::RecordInvalid => e
      { error: e.message }
    end

    def cancel(order:)
      return { error: "Cut-off dépassé" } if order.bake_day.cut_off_passed?
      return { error: "Pas une commande planifiée" } unless order.planned?

      order.destroy!
      { success: true }
    rescue ActiveRecord::RecordNotDestroyed => e
      { error: e.message }
    end
  end
end
