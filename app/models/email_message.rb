class EmailMessage < ApplicationRecord
  enum :direction, {
    outbound: 0,
    inbound: 1
  }

  enum :kind, {
    confirmation: 0,
    otp: 1,
    other: 2
  }

  belongs_to :customer, optional: true
  belongs_to :order, optional: true

  validates :to_email, presence: true
  validates :from_email, presence: true
  validates :body_html, presence: true
  validates :direction, presence: true
  validates :kind, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_customer, ->(customer) { where(customer_id: customer.id) }
  scope :ordered_by_sent_at, -> { order(sent_at: :desc, created_at: :desc) }
end
