# frozen_string_literal: true

# Lieu de vente (#150) : un endroit où la boulangerie vend (typiquement un
# marché), porteur d'un COÛT (emplacement / stand) qui se déduit du bénéfice.
#
# Concept SÉPARÉ du lieu de retrait (`PickupLocation`) — décision produit : on ne
# les fusionne pas. Ici on ne gère QUE le coût (pas les recettes/ventes par lieu).
#
# Suppression = soft delete (comme MoldType / PickupLocation) : un lieu retiré
# disparaît des sélecteurs mais reste lisible sur les fournées passées qui le
# référencent. Aucun `default_scope` n'est posé — filtrer explicitement avec
# `not_deleted` dans les sélecteurs.
class SalesLocation < ApplicationRecord
  has_soft_deletion

  has_many :sales_location_costs, dependent: :destroy
  has_many :bake_day_sales_locations, dependent: :destroy
  has_many :bake_days, through: :bake_day_sales_locations

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :active, -> { not_deleted.where(active: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  # Coût (cents) applicable à une date donnée, ou `nil` si aucune période ne la
  # couvre (le lieu n'a donc aucun coût déductible à cette date). Délègue au
  # résolveur du modèle de coût historisé.
  def cost_cents(on: Date.current)
    SalesLocationCost.cost_cents_for(self, on: on)
  end
end
