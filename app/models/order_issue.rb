# Problème signalé par le client sur une commande retirée (#remboursement-partiel).
#
# C'est une DEMANDE, pas une décision : elle ouvre la conversation avec les
# boulangers, qui remboursent ce qu'ils veulent — ou rien. L'état `resolved`
# signifie « traité », pas « remboursé ».
class OrderIssue < ApplicationRecord
  DESCRIPTION_MAX_LENGTH = 1000

  enum :state, { open: 0, resolved: 1 }, prefix: :state

  belongs_to :order
  belongs_to :customer
  has_many :order_issue_items, dependent: :destroy
  has_many :order_items, through: :order_issue_items
  # Les remboursements décidés en réponse à ce signalement. `nullify` : effacer
  # un signalement ne doit jamais effacer la trace d'un mouvement d'argent.
  has_many :partial_refunds, dependent: :nullify

  accepts_nested_attributes_for :order_issue_items, allow_destroy: true

  validates :description, presence: true, length: { maximum: DESCRIPTION_MAX_LENGTH }

  scope :recent, -> { order(created_at: :desc) }

  def resolve!(by: nil)
    update!(state: :resolved, resolved_at: Time.current, resolved_by: by)
  end

  # Quantité signalée pour une ligne de commande donnée — ce que le formulaire de
  # remboursement pré-coche.
  def reported_qty_for(order_item)
    order_issue_items.detect { |item| item.order_item_id == order_item.id }&.qty || 0
  end
end
