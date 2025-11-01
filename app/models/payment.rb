class Payment < ApplicationRecord
  enum status: {
    succeeded: 0,
    failed: 1,
    refunded: 2
  }

  belongs_to :order

  validates :stripe_payment_intent_id, presence: true, uniqueness: true
  validates :status, presence: true

  scope :succeeded, -> { where(status: :succeeded) }

  def refunded?
    status == 'refunded'
  end

  def succeeded?
    status == 'succeeded'
  end
end

