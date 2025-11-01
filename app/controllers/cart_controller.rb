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
      redirect_to catalog_path, alert: 'Ce produit n\'est pas disponible'
      return
    end

    session[:bake_day_id] = bake_day_id if bake_day_id.present?
    session[:cart] ||= []

    existing_item = session[:cart].find { |item| item['product_variant_id'] == variant.id.to_s }

    if existing_item
      existing_item['qty'] = existing_item['qty'].to_i + (params[:qty].to_i || 1)
    else
      session[:cart] << {
        'product_variant_id' => variant.id.to_s,
        'qty' => (params[:qty] || 1).to_i,
        'name' => variant.name,
        'price_cents' => variant.price_cents
      }
    end

    redirect_to cart_path, notice: 'Produit ajouté au panier'
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
end

