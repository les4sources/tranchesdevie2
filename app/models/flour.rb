# frozen_string_literal: true

class Flour < ApplicationRecord
  has_soft_deletion

  has_many :product_flours, dependent: :restrict_with_error

  # Levain associé à la farine (deux levains à la boulangerie : froment, seigle).
  enum :levain_type, { froment: "froment", seigle: "seigle" }

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validates :levain_type, presence: true
  validates :flour_ratio, :water_ratio, :salt_ratio, :levain_ratio,
            presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :price_per_kg_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :not_deleted, -> { where(deleted_at: nil) }

  def price_per_kg_euros
    return nil if price_per_kg_cents.nil?

    (price_per_kg_cents / 100.0).round(2)
  end

  def price_per_kg_euros=(value)
    self.price_per_kg_cents = value.to_s.strip.blank? ? nil : (value.to_s.tr(",", ".").to_f * 100).round
  end
end
