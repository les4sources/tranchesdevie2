class SmsTemplate < ApplicationRecord
  CATEGORIES = %w[UTILITY AUTHENTICATION MARKETING].freeze

  validates :name, presence: true, uniqueness: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :language, presence: true
  validates :body, presence: true

  scope :synced, -> { where.not(external_id: nil) }

  def synced?
    external_id.present?
  end
end
