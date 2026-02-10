class Group < ApplicationRecord
  has_many :customer_groups, dependent: :destroy
  has_many :customers, through: :customer_groups
  has_many :variant_group_restrictions, dependent: :destroy
  has_many :restricted_variants, through: :variant_group_restrictions, source: :product_variant

  validates :name, presence: true
  validates :discount_percent, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
end

