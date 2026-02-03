class CatalogController < ApplicationController
  def index
    @products = load_all_active_products
    @seasonal_promotion = seasonal_promotion_content
  end

  private

  def load_all_active_products
    Product.not_deleted.active.store_channel.ordered.includes(
      product_variants: [:variant_group_restrictions, { product_images: :image_attachment }],
      product_images: :image_attachment
    ).map do |product|
      variants = product.product_variants.active.store_channel.visible_to_customer(current_customer)
      [product, variants] if variants.any?
    end.compact
  end

  def seasonal_promotion_content
    {
      title: "🧀 Bientôt la première Camembert Party de 2026 !",
      description: "Viens aux 4 Sources ce 13 février pour déguster une \"mini-fondue\" en trempant du pain frais dans ton fromage tout juste sorti du four et dégoulinant à point ! 😋 Le tout accompagné de tes petits légumes préférés ! ",
      cta_text: "Infos et réservations",
      cta_path: "https://www.les4sources.be/evenements/camembert-party-10-octobre-2025"
    }
  end
end

