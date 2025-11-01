class CatalogController < ApplicationController
  def index
    @bake_day = find_bake_day
    @products = load_products_for_bake_day(@bake_day)
  end

  private

  def find_bake_day
    if params[:bake_day].present?
      date = Date.parse(params[:bake_day]) rescue nil
      BakeDay.find_by(baked_on: date) if date
    end || BakeDayService.next_available_bake_day
  end

  def load_products_for_bake_day(bake_day)
    return Product.none unless bake_day

    Product.active.ordered.includes(:product_variants).map do |product|
      variants = product.product_variants.active.select do |variant|
        variant.available_on?(bake_day.baked_on)
      end
      [product, variants] if variants.any?
    end.compact
  end
end

