class CartController < ApplicationController
  def show
    @cart = session[:cart] || []
    @bake_day_id = session[:bake_day_id]
    @bake_day = BakeDay.find_by(id: @bake_day_id) if @bake_day_id
    @subtotal = calculate_subtotal
    @customer = current_customer_for_cart
    @discount_cents = calculate_discount(@subtotal, @customer)
    @total = @subtotal - @discount_cents
    @available_bake_days = load_next_available_bake_days
    @phone_e164 = session[:phone_e164] if phone_verified?
    # Vérifier si le bake_day actuel est toujours disponible
    if @bake_day && !@bake_day.can_order?
      @bake_day = nil
      @bake_day_id = nil
      session[:bake_day_id] = nil
    end
  end

  def add
    variant = ProductVariant.find(params[:product_variant_id])
    bake_day_id = params[:bake_day_id]

    unless variant.active?
      respond_to do |format|
        format.html { redirect_to catalog_path, alert: 'Ce produit n\'est pas disponible' }
        format.json { render json: { error: 'Ce produit n\'est pas disponible' }, status: :unprocessable_entity }
      end
      return
    end

    session[:bake_day_id] = bake_day_id if bake_day_id.present?
    session[:cart] ||= []

    existing_item = session[:cart].find { |item| item['product_variant_id'] == variant.id.to_s }

    if existing_item
      existing_item['qty'] = existing_item['qty'].to_i + requested_quantity
    else
      session[:cart] << {
        'product_variant_id' => variant.id.to_s,
        'qty' => requested_quantity,
        'name' => variant.name,
        'price_cents' => variant.price_cents
      }
    end

    respond_to do |format|
      format.html { redirect_to cart_path, notice: 'Produit ajouté au panier' }
      format.json do
        render json: {
          cart_count: current_cart_count,
          variant_qty: current_cart_variant_qty(variant.id),
          message: success_message(variant),
          mini_cart_html: render_to_string(
            partial: 'cart/mini_cart',
            formats: [:html],
            locals: {
              items: current_cart_items,
              total_cents: current_cart_total_cents,
              subtotal_cents: current_cart_subtotal_cents,
              discount_cents: current_cart_discount_cents,
              customer: current_customer_for_cart,
              count: current_cart_count
            }
          )
        }, status: :created
      end
    end
  end

  def update
    cart = session[:cart] || []
    item = cart.find { |i| i['product_variant_id'] == params[:id] }

    if item && params[:qty].to_i > 0
      item['qty'] = params[:qty].to_i
      session[:cart] = cart
      redirect_to cart_path, notice: 'Panier mis à jour'
    else
      redirect_to cart_path, alert: 'Quantité invalide'
    end
  end

  def remove
    session[:cart] = (session[:cart] || []).reject { |item| item['product_variant_id'] == params[:id] }
    redirect_to cart_path, notice: 'Produit retiré du panier'
  end

  def update_bake_day
    bake_day = BakeDay.find_by(id: params[:bake_day_id])
    
    if bake_day && bake_day.can_order?
      session[:bake_day_id] = bake_day.id
      respond_to do |format|
        format.json { render json: { success: true, bake_day_id: bake_day.id } }
        format.html { redirect_to cart_path }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, error: 'Jour de cuisson non disponible' }, status: :unprocessable_entity }
        format.html { redirect_to cart_path, alert: 'Jour de cuisson non disponible' }
      end
    end
  end

  def logout
    session[:customer_id] = nil
    session[:customer_authenticated_at] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
    redirect_to cart_path, notice: 'Déconnexion réussie'
  end

  private

  def calculate_subtotal
    (session[:cart] || []).sum do |item|
      item['qty'].to_i * item['price_cents'].to_i
    end
  end

  def calculate_discount(subtotal, customer)
    return 0 unless customer&.group&.discount_percent

    (subtotal * customer.group.discount_percent / 100.0).round
  end

  def requested_quantity
    qty = params[:qty].to_i
    qty.positive? ? qty : 1
  end

  def success_message(variant)
    product_name = variant.product&.name
    variant_name = variant.name

    if product_name.present? && variant_name.present?
      "#{product_name} (#{variant_name}) ajouté à ton panier"
    elsif product_name.present?
      "#{product_name} ajouté à ton panier"
    else
      "#{variant_name.presence || 'Produit'} ajouté à ton panier"
    end
  end

  def load_next_available_bake_days
    # Récupérer tous les jours de cuisson futurs disponibles (mardis et vendredis)
    available_bake_days = BakeDay.future
                                  .where('cut_off_at > ?', Time.current)
                                  .ordered
                                  .select { |bd| bd.can_order? && [2, 5].include?(bd.baked_on.wday) }
    
    # Grouper par jour de la semaine et prendre le premier de chaque groupe
    tuesday_bake_days = available_bake_days.select { |bd| bd.baked_on.wday == 2 }
    friday_bake_days = available_bake_days.select { |bd| bd.baked_on.wday == 5 }
    
    result = []
    result << tuesday_bake_days.first if tuesday_bake_days.any?
    result << friday_bake_days.first if friday_bake_days.any?
    
    result.compact.sort_by(&:baked_on)
  end
end

