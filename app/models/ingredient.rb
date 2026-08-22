class Ingredient < ApplicationRecord
  has_soft_deletion

  enum :unit_type, { weight: 0, piece: 1 }

  has_many :variant_ingredients, dependent: :restrict_with_error
  has_many :product_variants, through: :variant_ingredients

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validates :unit_type, presence: true

  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :not_deleted, -> { where(deleted_at: nil) }

  def unit_label
    weight? ? "g" : "pièce(s)"
  end
end
