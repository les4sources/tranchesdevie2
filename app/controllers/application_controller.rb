class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include CustomerAuthentication

  helper_method :current_cart_items, :current_cart_total_cents, :current_cart_count, :current_cart_variant_qty, :phone_verified?

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

  def current_cart_variant_qty(variant_id)
    cart = session[:cart] || []
    item = cart.find { |i| i['product_variant_id'] == variant_id.to_s }
    item ? item['qty'].to_i : 0
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

  def phone_verified?
    # Si le client est connecté, considérer le téléphone comme vérifié
    if customer_signed_in?
      # Synchroniser la session avec les données du client connecté
      session[:phone_e164] = current_customer.phone_e164
      session[:otp_verified] = true
      session[:otp_verified_at] = Time.current.to_i
      return true
    end
    
    # Sinon, vérifier la session OTP classique
    return false unless session[:otp_verified] == true
    return false unless session[:otp_verified_at].present?
    return false unless session[:phone_e164].present?
    
    verified_at = Time.at(session[:otp_verified_at])
    verified_at > 1.year.ago
  end
end
