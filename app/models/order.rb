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

  COMPLETED_STATUSES = %w[paid ready picked_up].freeze

  before_validation :generate_public_token, on: :create
  before_validation :generate_order_number, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :by_bake_day, ->(bake_day) { where(bake_day: bake_day) }
  scope :completed, -> { where(status: COMPLETED_STATUSES) }
  scope :in_bake_day_range, lambda { |start_date, end_date|
    joins(:bake_day).where(bake_days: { baked_on: start_date..end_date })
  }

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

  class << self
    def revenue_between(start_date, end_date)
      completed.in_bake_day_range(start_date, end_date).sum(:total_cents)
    end

    def sales_by_product_between(start_date, end_date)
      total_quantity = Arel.sql('SUM(order_items.qty)')
      total_revenue = Arel.sql('SUM(order_items.qty * order_items.unit_price_cents)')

      completed
        .in_bake_day_range(start_date, end_date)
        .joins(order_items: { product_variant: :product })
        .group('products.id', 'products.name')
        .order(total_revenue.desc)
        .pluck(
          'products.name',
          total_quantity,
          total_revenue
        ).map do |name, total_quantity, total_cents|
          {
            product_name: name,
            total_quantity: total_quantity.to_i,
            total_cents: total_cents.to_i
          }
        end
    end

    def top_customers_between(start_date, end_date, limit: 10)
      orders_count = Arel.sql('COUNT(DISTINCT orders.id)')
      total_revenue = Arel.sql('SUM(orders.total_cents)')

      completed
        .in_bake_day_range(start_date, end_date)
        .joins(:customer)
        .group('customers.id', 'customers.first_name', 'customers.last_name')
        .order(total_revenue.desc)
        .limit(limit)
        .pluck(
          'customers.first_name',
          'customers.last_name',
          orders_count,
          total_revenue
        ).map do |first_name, last_name, orders_count, total_cents|
          {
            customer_name: [first_name, last_name].compact.join(' ').strip,
            orders_count: orders_count.to_i,
            total_cents: total_cents.to_i
          }
        end
    end

    def sales_by_weekday_between(start_date, end_date, weekdays)
      completed
        .in_bake_day_range(start_date, end_date)
        .joins(:bake_day)
        .where('EXTRACT(DOW FROM bake_days.baked_on) IN (?)', weekdays)
        .group(Arel.sql('EXTRACT(DOW FROM bake_days.baked_on)'))
        .order(Arel.sql('EXTRACT(DOW FROM bake_days.baked_on)'))
        .pluck(
          Arel.sql('EXTRACT(DOW FROM bake_days.baked_on)::integer'),
          Arel.sql('COUNT(DISTINCT orders.id)'),
          Arel.sql('SUM(orders.total_cents)')
        ).map do |weekday, orders_count, total_cents|
          {
            weekday: weekday,
            orders_count: orders_count.to_i,
            total_cents: total_cents.to_i
          }
        end
    end

    def sales_by_month_between(start_date, end_date)
      completed
        .in_bake_day_range(start_date, end_date)
        .joins(:bake_day)
        .group(Arel.sql("DATE_TRUNC('month', bake_days.baked_on)"))
        .order(Arel.sql("DATE_TRUNC('month', bake_days.baked_on)"))
        .pluck(
          Arel.sql("DATE_TRUNC('month', bake_days.baked_on)"),
          Arel.sql('COUNT(DISTINCT orders.id)'),
          Arel.sql('SUM(orders.total_cents)')
        ).map do |month, orders_count, total_cents|
          {
            month: month.to_date,
            orders_count: orders_count.to_i,
            total_cents: total_cents.to_i
          }
        end
    end
  end

  private

  def generate_public_token
    return if public_token.present?

    loop do
      # Generate 16 random bytes and convert to integer for Base58 encoding
      bytes = SecureRandom.random_bytes(16)
      # Convert bytes to integer (big-endian, treating as 128-bit number)
      integer = bytes.unpack1('H*').to_i(16)
      self.public_token = Base58.encode(integer)[0..23]
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

