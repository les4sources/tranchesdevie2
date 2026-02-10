# frozen_string_literal: true

class Artisan < ApplicationRecord
  has_many :bake_day_artisans, dependent: :destroy
  has_many :bake_days, through: :bake_day_artisans

  validates :name, presence: true

  scope :active, -> { where(active: true) }
end
