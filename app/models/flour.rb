# frozen_string_literal: true

class Flour < ApplicationRecord
  has_soft_deletion

  has_many :product_flours, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }

  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :not_deleted, -> { where(deleted_at: nil) }
end
