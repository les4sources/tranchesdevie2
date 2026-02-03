class VariantGroupRestriction < ApplicationRecord
  belongs_to :product_variant
  belongs_to :group

  validates :group_id, uniqueness: { scope: :product_variant_id }
end
