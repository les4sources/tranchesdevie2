class Group < ApplicationRecord
  has_many :customer_groups, dependent: :destroy
  has_many :customers, through: :customer_groups
  has_many :variant_group_restrictions, dependent: :destroy
  has_many :restricted_variants, through: :variant_group_restrictions, source: :product_variant
  has_many :group_product_discounts, dependent: :destroy

  accepts_nested_attributes_for :group_product_discounts, allow_destroy: true,
                                reject_if: ->(attrs) { attrs[:target].blank? && attrs[:discount_value_raw].blank? }

  validates :name, presence: true
  validates :discount_percent, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  # Remise ciblée applicable à une variante donnée : la plus spécifique gagne
  # (variante > produit). Opère sur la collection chargée (pas de requête).
  def discount_for(variant)
    group_product_discounts.detect { |d| d.product_variant_id == variant.id } ||
      group_product_discounts.detect { |d| d.product_id == variant.product_id && d.product_variant_id.nil? }
  end
end
