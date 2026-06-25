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

  # Le paiement réel est la source de vérité du `payment_status` de la commande
  # (cf. #41) : à chaque création/modification d'un paiement, on resynchronise.
  after_commit :sync_order_payment_status

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

  private

  def sync_order_payment_status
    order&.sync_payment_status!
  end
end
