class SmsMessage < ApplicationRecord
  enum direction: {
    outbound: 0,
    inbound: 1
  }

  enum kind: {
    confirmation: 0,
    ready: 1,
    refund: 2,
    other: 3
  }

  validates :to_e164, presence: true
  validates :from_e164, presence: true
  validates :body, presence: true
  validates :direction, presence: true
  validates :kind, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_phone, ->(phone) { where(to_e164: phone) }

  def self.create_inbound(from, to, body)
    kind = if body.upcase.strip == 'STOP'
             :other # Will be handled by webhook processor
           else
             :other
           end

    create!(
      direction: :inbound,
      from_e164: from,
      to_e164: to,
      body: body,
      kind: kind
    )
  end
end

