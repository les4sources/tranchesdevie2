class CatalogController < ApplicationController
  def index
    @products = load_all_active_products
    @seasonal_promotion = seasonal_promotion_content
  end

  private

  def load_all_active_products
    Product.active.ordered.includes(
      product_variants: { product_images: :image_attachment },
      product_images: :image_attachment
    ).map do |product|
      variants = product.product_variants.active
      [product, variants] if variants.any?
    end.compact
  end

  def seasonal_promotion_content
    {
      title: "Ça y est, on cuit le mardi, et on a un site !",
      description: "Hourra, le four à pain des 4 Sources va désormais chauffer pour vous les mardis et vendredis 🎉 Commandez dès maintenant vos pains pour la semaine prochaine.",
      cta_text: "",
      cta_path: nil
    }
  end
end

