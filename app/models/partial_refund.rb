# Remboursement partiel d'une commande livrée (#remboursement-partiel).
#
# Un enregistrement = un mouvement d'argent réellement effectué. La table est la
# source de vérité du montant rendu sur une commande : ni `orders.status` ni
# `orders.payment_status` ne bougent pour un remboursement partiel (la commande
# a été livrée et encaissée, on en rend un morceau).
class PartialRefund < ApplicationRecord
  # `cash` ne déclenche aucun mouvement automatique : l'app ne manipule pas
  # d'espèces. Le boulanger rend les pièces et enregistre la trace, sans quoi le
  # reporting ignorerait de l'argent sorti du tiroir.
  enum :channel, { stripe: 0, wallet: 1, cash: 2 }, prefix: :channel

  belongs_to :order
  belongs_to :order_issue, optional: true
  belongs_to :wallet_transaction, optional: true
  has_many :partial_refund_items, dependent: :destroy
  has_many :order_items, through: :partial_refund_items

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :recent, -> { order(created_at: :desc) }
  # Même axe temporel que le CA : le jour de cuisson (ou l'événement) de la
  # commande remboursée, jamais la date du clic.
  scope :in_event_date_range, lambda { |start_date, end_date|
    where(order_id: Order.in_event_date_range(start_date, end_date).select(:id))
  }

  def amount_euros
    (amount_cents / 100.0).round(2)
  end
end
