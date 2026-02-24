# frozen_string_literal: true

class MoldType < ApplicationRecord
  has_soft_deletion

  has_many :product_variants, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validates :limit, presence: true, numericality: { greater_than: 0, only_integer: true }

  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :not_deleted, -> { where(deleted_at: nil) }
end
