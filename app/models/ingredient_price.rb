# frozen_string_literal: true

# Palier de prix au kilo d'un ingrédient (#209). « On va acheter des figues et
# puis on va en racheter, ça ne va pas être le même prix. »
#
# On n'écrase jamais un prix : on ajoute un palier avec sa date d'effet, et le
# reporting d'une période passée continue de résoudre l'ancien.
class IngredientPrice < ApplicationRecord
  belongs_to :ingredient

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
