class CatalogController < ApplicationController
  def index
    @bake_day = find_bake_day
    @products = load_products_for_bake_day(@bake_day)
    @available_bake_days = load_available_bake_days
    @available_bake_days = (@available_bake_days + Array(@bake_day)).compact.uniq.sort_by(&:baked_on)
    @seasonal_promotion = seasonal_promotion_content
  end

  private

  def load_available_bake_days
    BakeDay.future.ordered.limit(2)
  end

  def find_bake_day
    if params[:bake_day].present?
      date = Date.parse(params[:bake_day]) rescue nil
      BakeDay.find_by(baked_on: date) if date
    end || BakeDayService.next_available_bake_day
  end

  def load_products_for_bake_day(bake_day)
    return [] unless bake_day

    Product.active.ordered.includes(:product_variants).map do |product|
      variants = product.product_variants.active.select do |variant|
        variant.available_on?(bake_day.baked_on)
      end
      [product, variants] if variants.any?
    end.compact
  end

  def seasonal_promotion_content
    {
      title: "Ça y est, on cuit le mardi !",
      description: "Le four à pain des 4 Sources va désormais chauffer pour vous les mardis et vendredis. Commandez dès maintenant vos pains pour la semaine prochaine.",
      cta_text: "C'est parti",
      cta_path: catalog_path
    }
  end
end

