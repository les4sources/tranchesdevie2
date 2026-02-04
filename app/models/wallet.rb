class Wallet < ApplicationRecord
  belongs_to :customer
  has_many :wallet_transactions, dependent: :destroy

  validates :balance_cents, numericality: { only_integer: true }
  validates :low_balance_threshold_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def credit!(amount_cents, type:, order: nil, stripe_payment_intent_id: nil, description: nil)
    transaction do
      wallet_transactions.create!(
        amount_cents: amount_cents,
        transaction_type: type,
        order: order,
        stripe_payment_intent_id: stripe_payment_intent_id,
        description: description
      )
      increment!(:balance_cents, amount_cents)
    end
  end

  def debit!(amount_cents, type:, order: nil, description: nil)
    credit!(-amount_cents, type: type, order: order, description: description)
  end

  def can_cover?(amount_cents)
    balance_cents >= amount_cents
  end

  def low_balance?
    balance_cents < low_balance_threshold_cents
  end

  def balance_euros
    (balance_cents / 100.0).round(2)
  end
end
