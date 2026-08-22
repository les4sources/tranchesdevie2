# frozen_string_literal: true

class ProductFlour < ApplicationRecord
  belongs_to :product
  belongs_to :flour

  validates :percentage, presence: true, numericality: { only_integer: true, in: 1..100 }
  validates :flour_id, uniqueness: { scope: :product_id }
  validate :product_percentages_sum_to_100, if: -> { product.present? }

  private

  def product_percentages_sum_to_100
    return if product.nil?
    # Use product.product_flours to include unsaved nested attributes
    collection = product.product_flours.reject(&:marked_for_destruction?)
    return if collection.empty? # No flour is allowed
    total = collection.sum { |pf| pf.percentage.to_i }
    return if total == 100
    errors.add(:base, "La somme des pourcentages doit être égale à 100%")
  end
end
