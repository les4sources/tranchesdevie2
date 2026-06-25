class Product < ApplicationRecord
  has_soft_deletion

  enum :category, { breads: 0, dough_balls: 1 }
  # Catégorie interne (usage comptable/reporting) : distingue la production
  # maison (boulangerie) des reventes (épicerie, traiteur, etc.).
  enum :internal_category, { boulangerie: 0, epicerie: 1, traiteur: 2, autre: 3 }, prefix: true

  has_many :product_variants, dependent: :destroy
  has_many :product_availabilities, through: :product_variants
  has_many :product_images, dependent: :destroy
  has_many :product_flours, dependent: :destroy
  has_many :flours, through: :product_flours

  accepts_nested_attributes_for :product_images, allow_destroy: true, reject_if: :reject_empty_image?
  accepts_nested_attributes_for :product_flours, allow_destroy: true

  validates :name, presence: true
  validates :category, presence: true
  validates :internal_category, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  validates :channel, presence: true, inclusion: { in: %w[store admin] }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(category: :asc, position: :asc, name: :asc) }
  scope :store_channel, -> { where(channel: "store") }
  scope :not_deleted, -> { where(deleted_at: nil) }

  def display_name
    name
  end

  def flour_composition_label
    return "Aucune" if product_flours.empty?

    product_flours.includes(:flour).map { |pf| "#{pf.flour.name} #{pf.percentage} %" }.join(", ")
  end

  # Un sac à pain est compté d'office pour chaque unité de PAIN PRODUIT (#52) :
  # catégorie « breads » et production maison (internal_category « boulangerie »).
  # Les pâtons (pâte à pizza, catégorie dough_balls) et les reventes (épicerie,
  # traiteur…) n'entraînent aucun coût de sac.
  def incurs_bag_cost?
    breads? && internal_category_boulangerie?
  end

  private

  def reject_empty_image?(attributes)
    Rails.logger.debug "reject_empty_image? called with: #{attributes.inspect}"

    # Don't reject if _destroy is set to true or '1' (we want to process deletions)
    destroy_value = attributes["_destroy"] || attributes[:_destroy]
    return false if destroy_value == true || destroy_value == "1" || destroy_value == 1

    # For existing records (with id), don't reject (allow updates without new image)
    return false if attributes["id"].present?

    # For new records, reject if no image is provided
    # Check both string and symbol keys
    image_value = attributes["image"] || attributes[:image]

    Rails.logger.debug "Image value: #{image_value.inspect}, blank?: #{image_value.blank?}"

    # Reject if image is blank or nil
    image_value.blank?
  end
end
