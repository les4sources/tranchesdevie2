# frozen_string_literal: true

# Animateur d'un atelier (#208). Pendant de `BakeDayArtisan` pour la production.
class WorkshopArtisan < ApplicationRecord
  belongs_to :workshop
  belongs_to :artisan

  validates :artisan_id, uniqueness: { scope: :workshop_id }
end
