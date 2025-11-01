class Order < ApplicationRecord
  enum :status, {
    pending: 0,
    paid: 1,
    ready: 2,
    picked_up: 3,
    no_show: 4,
    cancelled: 5
  }

  belongs_to :customer
  belongs_to :bake_day
  has_many :order_items, dependent: :destroy
  has_one :payment, dependent: :destroy

  validates :total_cents, presence: true, numericality: { greater_than: 0 }
  validates :public_token, presence: true, uniqueness: true
  validates :order_number, presence: true, uniqueness: true
  validates :status, presence: true

  before_validation :generate_public_token, on: :create
  before_validation :generate_order_number, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :by_bake_day, ->(bake_day) { where(bake_day: bake_day) }

  def total_euros
    (total_cents / 100.0).round(2)
  end

  def can_transition_to?(new_status)
    case status.to_sym
    when :pending
      new_status.to_sym == :paid
    when :paid
      [:ready, :cancelled].include?(new_status.to_sym)
    when :ready
      [:picked_up, :no_show].include?(new_status.to_sym)
    else
      false
    end
  end

  def transition_to!(new_status)
    raise ArgumentError, "Invalid transition from #{status} to #{new_status}" unless can_transition_to?(new_status)

    update!(status: new_status)
  end

  private

  def generate_public_token
    return if public_token.present?

    loop do
      self.public_token = Base58.encode(SecureRandom.random_bytes(16))[0..23]
      break unless Order.exists?(public_token: public_token)
    end
  end

  def generate_order_number
    return if order_number.present?

    date_str = Date.current.strftime('%Y%m%d')
    last_order = Order.where('order_number LIKE ?', "TV-#{date_str}-%")
                      .order(:order_number)
                      .last

    sequence = if last_order&.order_number&.match(/TV-\d{8}-(\d{4})/)
                 last_order.order_number.match(/TV-\d{8}-(\d{4})/)[1].to_i + 1
               else
                 1
               end

    self.order_number = "TV-#{date_str}-#{sequence.to_s.rjust(4, '0')}"
  end
end

