class WalletTransaction < ApplicationRecord
  belongs_to :wallet
  belongs_to :order, optional: true

  enum :transaction_type, { top_up: 0, order_debit: 1, order_refund: 2 }

  validates :amount_cents, presence: true
  validates :transaction_type, presence: true

  def amount_euros
    (amount_cents / 100.0).round(2)
  end
end
