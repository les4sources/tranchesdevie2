class CartController < ApplicationController
  def show
    @cart = session[:cart] || []
    @bake_day_id = session[:bake_day_id]
    @bake_day = BakeDay.find_by(id: @bake_day_id) if @bake_day_id
    @total = calculate_total
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
          message: success_message(variant),
          mini_cart_html: render_to_string(
            partial: 'cart/mini_cart',
            formats: [:html],
            locals: {
              items: current_cart_items,
              total_cents: current_cart_total_cents,
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

  private

  def calculate_total
    (session[:cart] || []).sum do |item|
      item['qty'].to_i * item['price_cents'].to_i
    end
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
end

