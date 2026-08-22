# frozen_string_literal: true

class BakeDayArtisan < ApplicationRecord
  belongs_to :bake_day
  belongs_to :artisan

  validates :bake_day_id, uniqueness: { scope: :artisan_id }
end
