class BakeDay < ApplicationRecord
  has_many :orders, dependent: :restrict_with_error

  validates :baked_on, presence: true, uniqueness: true
  validates :cut_off_at, presence: true

  scope :future, -> { where('baked_on >= ?', Date.current) }
  scope :past, -> { where('baked_on < ?', Date.current) }
  scope :ordered, -> { order(:baked_on) }

  def can_order?
    Time.current < cut_off_at
  end

  def cut_off_passed?
    !can_order?
  end

  def total_breads_count
    orders
      .joins(order_items: { product_variant: :product })
      .where(products: { category: :breads })
      .where.not(orders: { status: :cancelled })
      .sum('order_items.qty')
  end

  def total_sales_euros
    orders
      .sum(:total_cents) / 100.0
  end

  class << self
    def next_available
      future.ordered.first
    end

    def calculate_cut_off_for(date)
      return nil unless [2, 5].include?(date.wday) # Tuesday (2) or Friday (5)

      # Tue ← Sun 18:00, Fri ← Wed 18:00 (Europe/Brussels)
      days_before = case date.wday
                    when 2 then 2 # Sunday before Tuesday
                    when 5 then 2 # Wednesday before Friday
                    else 0
                    end

      cut_off_date = date - days_before.days
      Time.zone.parse("#{cut_off_date} 18:00:00")
    end
  end
end

