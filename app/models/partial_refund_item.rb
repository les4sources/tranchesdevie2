class PartialRefundItem < ApplicationRecord
  belongs_to :partial_refund
  belongs_to :order_item

  validates :qty, numericality: { only_integer: true, greater_than: 0 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def amount_euros
    (amount_cents / 100.0).round(2)
  end
end
