class ProductImage < ApplicationRecord
  belongs_to :product
  belongs_to :product_variant, optional: true

  has_one_attached :image

  validates :product, presence: true
  validate :product_variant_belongs_to_product
  
  # Auto-set product_id from product_variant if not set
  before_validation :set_product_from_variant, if: -> { product_variant.present? && product_id.blank? }
  before_validation :set_position, on: :create, if: -> { position.nil? }

  scope :for_variant, ->(variant) { where(product_variant: variant) }
  scope :without_variant, -> { where(product_variant_id: nil) }
  scope :ordered, -> { order(:position, :created_at) }

  private

  def set_product_from_variant
    self.product_id = product_variant.product_id
  end

  def product_variant_belongs_to_product
    return if product_variant.nil?

    unless product_variant.product_id == product_id
      errors.add(:product_variant, "must belong to the same product")
    end
  end

  def set_position
    if product_variant.present?
      max_position = product_variant.product_images.maximum(:position) || 0
      self.position = max_position + 1
    else
      max_position = product.product_images.without_variant.maximum(:position) || 0
      self.position = max_position + 1
    end
  end
end

