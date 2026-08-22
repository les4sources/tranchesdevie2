class WalletTransaction < ApplicationRecord
  belongs_to :wallet
  belongs_to :order, optional: true

  enum :transaction_type, { top_up: 0, order_debit: 1, order_refund: 2 }

  validates :amount_cents, presence: true
  validates :transaction_type, presence: true

  # Les débits/remboursements de commande participent à la source de vérité du
  # `payment_status` de la commande (cf. #41). Les recharges (`top_up`) ne sont
  # pas liées à une commande et n'ont aucun effet ici.
  after_commit :sync_order_payment_status

  def amount_euros
    (amount_cents / 100.0).round(2)
  end

  private

  def sync_order_payment_status
    order&.sync_payment_status!
  end
end
