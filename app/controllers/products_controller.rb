class ProductsController < ApplicationController
  def show
    @product = Product.not_deleted.active.store_channel.find(params[:id])

    # Les pizza parties (privée & publique) se réservent depuis la page
    # Événements, pas depuis le catalogue (#pizza-parties). On y redirige toute
    # arrivée directe.
    if @product.pizza_party_role_party? || @product.pizza_party_role_public_party?
      redirect_to pizza_party_privee_path and return
    end

    @variants = @product.product_variants.active.store_channel.visible_to_customer(current_customer).order(:name)

    # Si un jour de cuisson est choisi, n'afficher que les variantes disponibles ce jour-là.
    if (selected_wday = selected_bake_day_wday)
      @variants = @variants.select { |v| v.available_on_weekday?(selected_wday) }
    end

    if @variants.empty?
      redirect_to catalog_path, alert: "Produit non disponible"
      return
    end

    # Collect all images from product and variants
    @product_images = []

    # Add product-level images first
    @product.product_images.without_variant.ordered.each do |product_image|
      next unless product_image.image.attached?

      image_url = if product_image.image.variable?
        rails_blob_url(product_image.image.variant(resize_to_limit: [ 1200, 1200 ]))
      else
        rails_blob_url(product_image.image)
      end

      @product_images << {
        url: image_url,
        variant_name: nil
      }
    end

    # Add variant images
    @variants.each do |variant|
      variant.product_images.ordered.each do |product_image|
        next unless product_image.image.attached?

        image_url = if product_image.image.variable?
          rails_blob_url(product_image.image.variant(resize_to_limit: [ 1200, 1200 ]))
        else
          rails_blob_url(product_image.image)
        end

        @product_images << {
          url: image_url,
          variant_name: variant.name
        }
      end
    end

    # Fallback to static image if no images found
    if @product_images.empty?
      # Try to use the first product image if available
      if @product.product_images.any? && @product.product_images.first.image.attached?
        product_image = @product.product_images.first.image
        if product_image.variable?
          fallback_url = rails_blob_url(product_image.variant(resize_to_limit: [ 1200, 1200 ]))
        else
          fallback_url = rails_blob_url(product_image)
        end
      else
        # Fallback to static image map
        fallback_url = CatalogHelper::PRODUCT_IMAGE_MAP.fetch(@product.name, CatalogHelper::CATEGORY_IMAGE_FALLBACKS[@product.category])
      end
      @product_images << { url: fallback_url, variant_name: nil }
    end

    # Set selected variant (first active variant by default)
    @selected_variant = @variants.first
  rescue ActiveRecord::RecordNotFound
    redirect_to catalog_path, alert: "Produit introuvable"
  end
end
