# frozen_string_literal: true

class ProductionSetting < ApplicationRecord
  validates :oven_capacity_grams, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :market_day_oven_capacity_grams, presence: true, numericality: { greater_than: 0, only_integer: true }

  def self.current
    first || create!
  end

  private

  def ensure_singleton
    if self.class.exists?
      errors.add(:base, "Il ne peut y avoir qu'un seul paramètre de production")
      throw(:abort)
    end
  end

  before_create :ensure_singleton
end
