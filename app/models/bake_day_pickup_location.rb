# frozen_string_literal: true

# Jointure « ce lieu de retrait est ouvert sur cette fournée » (#148).
# Calquée sur BakeDayArtisan.
class BakeDayPickupLocation < ApplicationRecord
  belongs_to :bake_day
  belongs_to :pickup_location

  validates :pickup_location_id, uniqueness: { scope: :bake_day_id }
end
