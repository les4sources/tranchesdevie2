class WalletTransaction < ApplicationRecord
  belongs_to :wallet
  belongs_to :order, optional: true

  # `order_refund` = remboursement INTÉGRAL (la commande est annulée avec).
  # `partial_refund` = quelques lignes rendues sur une commande livrée
  # (#remboursement-partiel) : elle reste payée, et `Order#payment_refunded?`
  # ne doit surtout pas s'allumer dessus.
  # `order_adjustment` = écart (signé) entre le débit initial et le nouveau
  # total quand le boulanger modifie une commande déjà débitée : négatif si la
  # commande grossit, positif si elle diminue.
  enum :transaction_type, { top_up: 0, order_debit: 1, order_refund: 2, partial_refund: 3, order_adjustment: 4 }

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
