class Group < ApplicationRecord
  has_many :customers, dependent: :nullify

  validates :name, presence: true
  validates :discount_percent, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
end

