class GroupProductDiscount < ApplicationRecord
  KINDS = %w[percent fixed].freeze

  belongs_to :group
  belongs_to :product, optional: true
  belongs_to :product_variant, optional: true

  # Valeur saisie dans le formulaire admin (pourcentage pour "percent",
  # euros pour "fixed"). Convertie en discount_value avant validation.
  attr_writer :discount_value_raw

  before_validation :apply_discount_value_raw

  validates :discount_kind, inclusion: { in: KINDS }
  validates :discount_value, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :percent_within_bounds
  validate :exactly_one_target
  validates :product_id, uniqueness: { scope: :group_id }, if: -> { product_id.present? && product_variant_id.blank? }
  validates :product_variant_id, uniqueness: { scope: :group_id }, if: -> { product_variant_id.present? }

  scope :for_product, ->(product_id) { where(product_id: product_id, product_variant_id: nil) }
  scope :for_variant, ->(variant_id) { where(product_variant_id: variant_id) }

  # Cible encodée pour le <select> admin : "variant_<id>" ou "product_<id>".
  def target
    if product_variant_id.present?
      "variant_#{product_variant_id}"
    elsif product_id.present?
      "product_#{product_id}"
    end
  end

  def target=(value)
    self.product_id = nil
    self.product_variant_id = nil
    return if value.blank?

    kind, id = value.to_s.split("_", 2)
    case kind
    when "variant" then self.product_variant_id = id
    when "product" then self.product_id = id
    end
  end

  def discount_value_raw
    return @discount_value_raw if defined?(@discount_value_raw) && @discount_value_raw
    return nil if discount_value.nil?

    discount_kind == "fixed" ? format("%.2f", discount_value / 100.0) : discount_value.to_s
  end

  # Réduction (en cents) appliquée à une unité au prix public `price_cents`.
  # Plancher à 0, plafonnée au prix (jamais de prix négatif).
  def unit_discount_cents(price_cents)
    raw = case discount_kind
    when "percent" then (price_cents * discount_value / 100.0).round
    when "fixed" then discount_value
    else 0
    end
    raw.clamp(0, price_cents)
  end

  private

  def apply_discount_value_raw
    return if @discount_value_raw.nil?

    raw = @discount_value_raw.to_s.tr(",", ".").strip
    if raw.blank?
      self.discount_value = nil
      return
    end

    self.discount_value = if discount_kind == "fixed"
      (BigDecimal(raw) * 100).round
    else
      raw.to_i
    end
  rescue ArgumentError
    self.discount_value = nil
  end

  def percent_within_bounds
    return unless discount_kind == "percent" && discount_value.present?

    errors.add(:discount_value, "doit être compris entre 0 et 100") if discount_value > 100
  end

  def exactly_one_target
    if product_id.blank? && product_variant_id.blank?
      errors.add(:base, "Sélectionnez un produit ou une variante")
    elsif product_id.present? && product_variant_id.present?
      errors.add(:base, "Choisissez soit un produit, soit une variante, pas les deux")
    end
  end
end
