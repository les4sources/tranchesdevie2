class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :product_availabilities, dependent: :destroy
  has_many :order_items, dependent: :restrict_with_error
  has_many :product_images, -> { ordered }, dependent: :destroy
  has_many :variant_ingredients, dependent: :destroy
  has_many :ingredients, through: :variant_ingredients
  has_many :variant_group_restrictions, dependent: :destroy
  has_many :restricted_groups, through: :variant_group_restrictions, source: :group

  def group_ids
    restricted_group_ids
  end

  def group_ids=(ids)
    self.restricted_group_ids = ids
  end

  accepts_nested_attributes_for :product_images, allow_destroy: true, reject_if: :reject_empty_image?
  accepts_nested_attributes_for :variant_ingredients, allow_destroy: true, reject_if: :reject_blank_ingredient?

  after_save :link_images_to_variant

  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0 }
  validates :channel, presence: true, inclusion: { in: %w[store admin] }

  scope :active, -> { where(active: true) }
  scope :store_channel, -> { where(channel: 'store') }

  scope :unrestricted, -> {
    where.not(id: VariantGroupRestriction.select(:product_variant_id))
  }

  scope :visible_to_customer, ->(customer) {
    if customer.nil? || customer.group_ids.empty?
      unrestricted
    else
      restricted_variant_ids = VariantGroupRestriction.select(:product_variant_id)
      allowed_variant_ids = VariantGroupRestriction.where(group_id: customer.group_ids).select(:product_variant_id)

      where.not(id: restricted_variant_ids).or(where(id: allowed_variant_ids))
    end
  }

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
    return nil if price_cents.nil?
    (price_cents / 100.0).round(2)
  end

  def price_euros=(value)
    self.price_cents = value.to_s.blank? ? nil : (value.to_f * 100).round
  end

  def restricted?
    variant_group_restrictions.any?
  end

  def visible_to?(customer)
    return true unless restricted?
    return false if customer.nil? || customer.group_ids.empty?

    restricted_groups.where(id: customer.group_ids).exists?
  end

  private

  def link_images_to_variant
    # Link images that were created via nested attributes but don't have variant_id yet
    # Only link images that belong to the same product
    product_images.where(product_variant_id: nil, product_id: product_id).update_all(product_variant_id: id)
  end

  def reject_empty_image?(attributes)
    # Don't reject if _destroy is set (we want to process deletions)
    return false if attributes['_destroy'].present?

    # For existing records (with id), don't reject (allow updates without new image)
    return false if attributes['id'].present?

    # For new records, reject if no image is provided
    image_value = attributes['image'] || attributes[:image]
    image_value.blank?
  end

  def reject_blank_ingredient?(attributes)
    # Don't reject if _destroy is set (we want to process deletions)
    return false if attributes['_destroy'].present?

    # For existing records (with id), don't reject
    return false if attributes['id'].present?

    # Reject if ingredient_id is blank
    attributes['ingredient_id'].blank?
  end
end

