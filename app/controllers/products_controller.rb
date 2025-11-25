class ProductsController < ApplicationController
  def show
    @product = Product.active.store_channel.find(params[:id])
    @variants = @product.product_variants.active.store_channel.order(:name)
    
    # Collect all images from product and variants
    @product_images = []
    
    # Add product-level images first
    @product.product_images.without_variant.ordered.each do |product_image|
      next unless product_image.image.attached?
      
      image_url = if product_image.image.variable?
        rails_blob_url(product_image.image.variant(resize_to_limit: [1200, 1200]))
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
          rails_blob_url(product_image.image.variant(resize_to_limit: [1200, 1200]))
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
          fallback_url = rails_blob_url(product_image.variant(resize_to_limit: [1200, 1200]))
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
    redirect_to catalog_path, alert: 'Produit introuvable'
  end
end

