class EmailMessage < ApplicationRecord
  enum :direction, {
    outbound: 0,
    inbound: 1
  }

  enum :kind, {
    confirmation: 0,
    otp: 1,
    other: 2,
    ready: 3,
    party_team_notification: 4,
    # Parcours de réservation Pizza party (#pizza-parties). Les cinq premiers
    # précèdent la validation et n'ont donc pas d'`order_id` : ils sont rattachés
    # à la demande (`party_request_id`).
    party_request_received: 5,
    party_request_team: 6,
    party_request_accepted: 7,
    party_request_refused: 8,
    party_request_expired: 9,
    party_payment_prompt: 10,
    party_payment_reminder: 11,
    party_payment_expired: 12,
    party_cancelled: 13,
    party_refunded: 14,
    # Information de la COMPTA qu'une party privée est encaissée (#289).
    # Ajouté en fin : les valeurs d'enum sont persistées en entier, intercaler
    # une valeur réétiquetterait tous les e-mails déjà journalisés.
    party_accounting_notification: 15,
    # Retrait qui s'est mal passé (#remboursement-partiel) : le signalement du
    # client part à l'équipe, le remboursement partiel part au client.
    order_issue_reported: 16,
    partial_refund: 17
  }

  belongs_to :customer, optional: true
  belongs_to :order, optional: true
  belongs_to :party_request, optional: true

  validates :to_email, presence: true
  validates :from_email, presence: true
  validates :body_html, presence: true
  validates :direction, presence: true
  validates :kind, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_customer, ->(customer) { where(customer_id: customer.id) }
  scope :ordered_by_sent_at, -> { order(sent_at: :desc, created_at: :desc) }
end
