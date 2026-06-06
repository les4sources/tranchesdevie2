class Payment < ApplicationRecord
  enum :status, {
    succeeded: 0,
    failed: 1,
    refunded: 2
  }

  belongs_to :order

  validates :stripe_payment_intent_id, presence: true, uniqueness: true
  validates :status, presence: true

  scope :succeeded, -> { where(status: :succeeded) }

  def refunded?
    status == "refunded"
  end

  def succeeded?
    status == "succeeded"
  end

  # Commission Stripe en euros (nil tant qu'elle n'a pas été récupérée).
  def stripe_fee_euros
    return nil if stripe_fee_cents.nil?

    (stripe_fee_cents / 100.0).round(2)
  end

  # Frais Stripe déjà récupérés depuis l'API ?
  def stripe_fee_recorded?
    !stripe_fee_cents.nil?
  end
end
