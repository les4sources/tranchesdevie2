# frozen_string_literal: true

class MoldType < ApplicationRecord
  has_soft_deletion

  has_many :product_variants, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validates :limit, presence: true, numericality: { greater_than: 0, only_integer: true }
  # Moules présents dans l'armoire. Vide = pas de contrainte sur deux fournées
  # consécutives (voir `BatchPacker`, priorité 1).
  validates :stock, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :not_deleted, -> { where(deleted_at: nil) }
end
