# frozen_string_literal: true

class DoughRatio < ApplicationRecord
  VALID_KEYS = %w[farine sel eau levain].freeze

  validates :key, presence: true, uniqueness: true, inclusion: { in: VALID_KEYS }
  validates :value, presence: true, numericality: { greater_than: 0 }
  validates :label, presence: true

  scope :ordered, -> { order(position: :asc) }

  def self.ratios_hash
    ordered.pluck(:key, :value).to_h
  end
end
