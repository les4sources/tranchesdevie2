class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_cart_items, :current_cart_total_cents, :current_cart_count

  private

  def current_cart_items
    @current_cart_items = build_cart_items(session[:cart] || [])
  end

  def current_cart_total_cents
    current_cart_items.sum { |item| item[:total_cents] }
  end

  def current_cart_count
    (session[:cart] || []).sum { |item| item['qty'].to_i }
  end

  def build_cart_items(cart)
    return [] if cart.blank?

    variant_ids = cart.map { |item| item['product_variant_id'] }.compact.uniq
    variants = ProductVariant.includes(:product).where(id: variant_ids).index_by { |variant| variant.id.to_s }

    cart.filter_map do |item|
      variant = variants[item['product_variant_id']]
      next unless variant

      qty = item['qty'].to_i

      {
        variant_id: variant.id,
        product_name: variant.product.name,
        variant_name: variant.name,
        qty: qty,
        price_cents: variant.price_cents,
        total_cents: variant.price_cents * qty
      }
    end
  end
end
