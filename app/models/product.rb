class Product < ApplicationRecord
  enum :category, { breads: 0, dough_balls: 1 }

  has_many :product_variants, dependent: :destroy
  has_many :product_availabilities, through: :product_variants

  validates :name, presence: true
  validates :category, presence: true
  validates :position, presence: true, numericality: { only_integer: true }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(category: :asc, position: :asc, name: :asc) }

  def display_name
    name
  end
end

