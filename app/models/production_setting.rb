# frozen_string_literal: true

class ProductionSetting < ApplicationRecord
  validates :oven_capacity_grams, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :market_day_oven_capacity_grams, presence: true, numericality: { greater_than: 0, only_integer: true }

  # Pain fourni aux Camembert Parties (#camembert-parties) : le grand froment
  # 1 kg. Sans lui, le tableau de la fournée n'a rien à substituer aux places et
  # le signale (cf. `Admin::BakeDayDashboard#camembert_breads`).
  belongs_to :camembert_bread_variant, class_name: "ProductVariant", optional: true

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
