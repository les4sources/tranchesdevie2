class VariantIngredient < ApplicationRecord
  belongs_to :product_variant
  belongs_to :ingredient

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :ingredient_id, uniqueness: { scope: :product_variant_id }

  delegate :unit_label, :unit_type, :weight?, :piece?, to: :ingredient
end
