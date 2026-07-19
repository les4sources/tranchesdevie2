# frozen_string_literal: true

# Exclusion produit ↔ lieu de retrait (#152). La présence d'une ligne signifie
# que le produit N'EST PAS commandable pour ce lieu de retrait. Exclusion au
# niveau PRODUIT, indépendante de la fournée. Sans rapport avec
# `variant_group_restrictions` (restriction par groupe client).
class ProductPickupLocationExclusion < ApplicationRecord
  belongs_to :product
  belongs_to :pickup_location

  validates :pickup_location_id, uniqueness: { scope: :product_id }
end
