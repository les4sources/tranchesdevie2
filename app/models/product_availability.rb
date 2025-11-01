class ProductAvailability < ApplicationRecord
  belongs_to :product_variant

  validates :start_on, presence: true
  validate :end_on_after_start_on

  scope :active_on, ->(date) { where('start_on <= ? AND (end_on IS NULL OR end_on >= ?)', date, date) }

  private

  def end_on_after_start_on
    return unless end_on.present? && start_on.present?

    errors.add(:end_on, 'must be after start_on') if end_on < start_on
  end
end

