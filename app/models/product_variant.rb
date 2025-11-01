class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :product_availabilities, dependent: :destroy
  has_many :order_items, dependent: :restrict_with_error

  has_one_attached :image

  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }

  def available_on?(date)
    return false unless active?

    # If no availabilities are defined, product is always available
    return true if product_availabilities.empty?

    product_availabilities.where(
      'start_on <= ? AND (end_on IS NULL OR end_on >= ?)',
      date, date
    ).exists?
  end

  def price_euros
    (price_cents / 100.0).round(2)
  end
end

