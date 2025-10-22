class StripeEvent < ApplicationRecord
  belongs_to :tenant, optional: true

  validates :event_id, presence: true, uniqueness: true

  def processed?
    processed_at.present?
  end

  def mark_processed!
    update!(processed_at: Time.current)
  end
end
