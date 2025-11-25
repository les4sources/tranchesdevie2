module CatalogHelper
  PRODUCT_IMAGE_MAP = {
    "Pain d'épeautre" => "https://images.unsplash.com/photo-1608198093002-ad4e005484ec?auto=format&fit=crop&w=800&q=80",
    "Pain au froment" => "https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=800&q=80",
    "Pain aux céréales anciennes" => "https://images.unsplash.com/photo-1486427944299-d1955d23e34d?auto=format&fit=crop&w=800&q=80",
    "Pain aux noix" => "https://images.unsplash.com/photo-1514996937319-344454492b37?auto=format&fit=crop&w=800&q=80",
    "Pain aux graines" => "https://images.unsplash.com/photo-1549931319-a545dcf3bc73?auto=format&fit=crop&w=800&q=80",
    "Pain aux noix/figues" => "https://images.unsplash.com/photo-1615397349754-e70a8542c7a8?auto=format&fit=crop&w=800&q=80",
    "Pain au chocolat/sucre" => "https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=800&q=80",
    "Boule de pâte à pizza à emporter" => "https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=80",
    "Boule de pâte à pizza pour Pizza Party privée" => "https://images.unsplash.com/photo-1512391801216-3c65a400cfb4?auto=format&fit=crop&w=800&q=80"
  }.freeze

  CATEGORY_IMAGE_FALLBACKS = {
    "breads" => "https://images.unsplash.com/photo-1608198093002-ad4e005484ec?auto=format&fit=crop&w=800&q=80",
    "dough_balls" => "https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=80"
  }.freeze

  def bake_day_label(bake_day)
    return "" unless bake_day

    weekday = I18n.with_locale(:fr) { I18n.l(bake_day.baked_on, format: "%A") }
    "Fournée du #{weekday}"
  end

  def bake_day_date_heading(bake_day)
    return "" unless bake_day

    I18n.with_locale(:fr) { I18n.l(bake_day.baked_on, format: "%A %d %B") }.capitalize
  end

  def bake_day_toggle_classes(bake_day, current_bake_day)
    base_classes = "flex h-full grow items-center justify-center overflow-hidden rounded-lg px-2 text-base font-medium leading-normal transition-shadow hover:shadow"
    selected_classes = "bg-white text-charcoal shadow-[0_0_4px_rgba(0,0,0,0.1)]"
    unselected_classes = "text-gray-500 hover:text-charcoal"

    class_names(base_classes, bake_day == current_bake_day ? selected_classes : unselected_classes)
  end

  def product_category_heading(category)
    case category
    when "breads" then "Pains"
    when "dough_balls" then "Pates a pizza"
    else category.to_s.tr("_", " ").capitalize
    end
  end

  def product_flour_label(flour)
    return "Aucune" if flour.blank?

    case flour
    when "wheat" then "Froment"
    when "spelled" then "Épeautre"
    when "ancien_wheat" then "Blé ancien"
    else flour.to_s.tr("_", " ").capitalize
    end
  end

  def product_background_image(product)
    # Try to use the first product image if available
    if product.product_images.any? && product.product_images.first.image.attached?
      product_image = product.product_images.first.image
      if product_image.variable?
        rails_blob_url(product_image.variant(resize_to_limit: [800, 800]))
      else
        rails_blob_url(product_image)
      end
    else
      # Fallback to static image map
      PRODUCT_IMAGE_MAP.fetch(product.name, CATEGORY_IMAGE_FALLBACKS[product.category])
    end
  end

  def variant_images_for_product(product, variants)
    # Collect all images from variants
    images = []
    variants.each do |variant|
      variant.product_images.each do |product_image|
        next unless product_image.image.attached?
        
        image_url = if product_image.image.variable?
          rails_blob_url(product_image.image.variant(resize_to_limit: [800, 800]))
        else
          rails_blob_url(product_image.image)
        end
        
        images << {
          url: image_url,
          variant_name: variant.name
        }
      end
    end
    
    # If no variant images, fallback to product image or static image
    if images.empty?
      fallback_url = product_background_image(product)
      images << { url: fallback_url, variant_name: nil }
    end
    
    images
  end

  def bake_day_picker_config(bake_days, current_bake_day)
    bake_days = Array(bake_days).compact.sort_by(&:baked_on)
    return nil if bake_days.empty?

    options = bake_days.map do |day|
      [
        bake_day_date_heading(day),
        day.baked_on.strftime("%Y-%m-%d")
      ]
    end

    values = options.map(&:last)
    value = current_bake_day&.baked_on&.strftime("%Y-%m-%d")
    value = values.include?(value) ? value : values.first

    {
      value: value,
      options: options
    }
  end
end

