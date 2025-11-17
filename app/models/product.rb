class Product < ApplicationRecord
  enum :category, { breads: 0, dough_balls: 1 }

  has_many :product_variants, dependent: :destroy
  has_many :product_availabilities, through: :product_variants
  has_many :product_images, dependent: :destroy

  accepts_nested_attributes_for :product_images, allow_destroy: true, reject_if: :reject_empty_image?

  validates :name, presence: true
  validates :category, presence: true
  validates :position, presence: true, numericality: { only_integer: true }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(category: :asc, position: :asc, name: :asc) }

  def display_name
    name
  end

  private

  def reject_empty_image?(attributes)
    Rails.logger.debug "reject_empty_image? called with: #{attributes.inspect}"
    
    # Don't reject if _destroy is set to true or '1' (we want to process deletions)
    destroy_value = attributes['_destroy'] || attributes[:_destroy]
    return false if destroy_value == true || destroy_value == '1' || destroy_value == 1
    
    # For existing records (with id), don't reject (allow updates without new image)
    return false if attributes['id'].present?
    
    # For new records, reject if no image is provided
    # Check both string and symbol keys
    image_value = attributes['image'] || attributes[:image]
    
    Rails.logger.debug "Image value: #{image_value.inspect}, blank?: #{image_value.blank?}"
    
    # Reject if image is blank or nil
    image_value.blank?
  end
end

