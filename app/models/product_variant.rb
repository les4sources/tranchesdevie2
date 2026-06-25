class ProductVariant < ApplicationRecord
  belongs_to :product
  belongs_to :mold_type, optional: true
  has_many :product_availabilities, dependent: :destroy
  has_many :order_items, dependent: :restrict_with_error
  has_many :product_images, -> { ordered }, dependent: :destroy
  has_many :variant_ingredients, dependent: :destroy
  has_many :ingredients, through: :variant_ingredients
  has_many :variant_group_restrictions, dependent: :destroy
  has_many :restricted_groups, through: :variant_group_restrictions, source: :group
  has_many :variant_cost_prices, dependent: :destroy

  def group_ids
    restricted_group_ids
  end

  def group_ids=(ids)
    self.restricted_group_ids = ids
  end

  accepts_nested_attributes_for :product_images, allow_destroy: true, reject_if: :reject_empty_image?
  accepts_nested_attributes_for :variant_ingredients, allow_destroy: true, reject_if: :reject_blank_ingredient?
  accepts_nested_attributes_for :variant_cost_prices, allow_destroy: true, reject_if: :reject_blank_cost_price?

  after_save :link_images_to_variant

  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0 }
  validates :channel, presence: true, inclusion: { in: %w[store admin] }

  scope :active, -> { where(active: true) }
  scope :store_channel, -> { where(channel: "store") }

  # Variantes disponibles pour un jour de cuisson donné (wday).
  # available_weekdays vide = aucune restriction (tous les jours de cuisson).
  scope :available_on_weekday, ->(wday) {
    where("cardinality(available_weekdays) = 0 OR ? = ANY(available_weekdays)", wday)
  }

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

  # Nettoie l'entrée du formulaire (cases à cocher + champ caché vide) en un
  # tableau d'entiers trié et dédoublonné. Tableau vide = aucune restriction.
  def available_weekdays=(values)
    cleaned = Array(values).map { |v| v.to_s.strip }.reject(&:blank?).map(&:to_i).uniq.sort
    super(cleaned)
  end

  # La variante est-elle restreinte à certains jours de cuisson ?
  def restricted_to_weekdays?
    available_weekdays.present?
  end

  # La variante est-elle disponible pour ce jour de la semaine (wday) ?
  # Aucune restriction (tableau vide) = disponible tous les jours.
  def available_on_weekday?(wday)
    return true unless restricted_to_weekdays?

    available_weekdays.include?(wday)
  end

  def available_on?(date)
    return false unless active?
    return false unless available_on_weekday?(date.wday)

    # If no availabilities are defined, product is always available
    return true if product_availabilities.empty?

    product_availabilities.where(
      "start_on <= ? AND (end_on IS NULL OR end_on >= ?)",
      date, date
    ).exists?
  end

  # Prix coûtant applicable à une date (#90), exposé pour le reporting (#54).
  # Renvoie le montant (cents) du palier le plus récent dont la date
  # d'activation est antérieure ou égale à `on`, ou `nil` si aucun palier n'est
  # actif à cette date (coûtant manquant signalé explicitement — pas de zéro
  # trompeur). Versionnement par date : insensible aux paliers postérieurs.
  def cost_price_cents(on: Date.current)
    variant_cost_prices
      .where(active_from: ..on)
      .ordered
      .limit(1)
      .pick(:amount_cents)
  end

  def cost_price_euros(on: Date.current)
    cents = cost_price_cents(on: on)
    return nil if cents.nil?

    (cents / 100.0).round(2)
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
    return false if attributes["_destroy"].present?

    # For existing records (with id), don't reject (allow updates without new image)
    return false if attributes["id"].present?

    # For new records, reject if no image is provided
    image_value = attributes["image"] || attributes[:image]
    image_value.blank?
  end

  def reject_blank_ingredient?(attributes)
    # Don't reject if _destroy is set (we want to process deletions)
    return false if attributes["_destroy"].present?

    # For existing records (with id), don't reject
    return false if attributes["id"].present?

    # Reject if ingredient_id is blank
    attributes["ingredient_id"].blank?
  end

  def reject_blank_cost_price?(attributes)
    # Don't reject deletions or existing records.
    return false if attributes["_destroy"].present?
    return false if attributes["id"].present?

    # Reject a brand-new blank row (no amount AND no date) so the spare
    # "add" row in the form is ignored when left empty.
    attributes["amount_euros"].to_s.strip.blank? && attributes["active_from"].to_s.strip.blank?
  end
end
