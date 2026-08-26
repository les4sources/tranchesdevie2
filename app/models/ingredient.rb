class Ingredient < ApplicationRecord
  include HistorisedKiloPrice

  has_soft_deletion

  # Prix au kilo historisés par date d'effet (#209).
  has_kilo_price_history :ingredient_prices

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
