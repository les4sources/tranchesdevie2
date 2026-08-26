# frozen_string_literal: true

# Palier de prix au kilo d'une farine (#209). Même mécanisme que
# `IngredientPrice` : le prix de la farine relève du même besoin.
class FlourPrice < ApplicationRecord
  belongs_to :flour

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :active_from, presence: true

  scope :ordered, -> { order(active_from: :desc, id: :desc) }

  def amount_euros
    return nil if amount_cents.nil?

    (amount_cents / 100.0).round(2)
  end

  def amount_euros=(value)
    self.amount_cents = value.to_s.strip.blank? ? nil : (value.to_s.tr(",", ".").to_f * 100).round
  end
end
