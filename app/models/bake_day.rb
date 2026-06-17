class BakeDay < ApplicationRecord
  # Source de vérité unique des jours de cuisson de la boulangerie.
  # Clé = wday (0=dimanche … 6=samedi), valeur = nombre de jours avant pour le cut-off (18:00).
  # Pour ajouter un jour de cuisson (ex. le jeudi), il suffit d'ajouter une entrée ici :
  # tout le reste (cut-off, panier, restriction de variante par jour) s'y adapte.
  COOKING_DAYS = { 2 => 2, 5 => 2 }.freeze # mardi ← dim 18:00, vendredi ← mer 18:00

  # Liste ordonnée des wday de cuisson, dérivée de COOKING_DAYS.
  COOKING_WDAYS = COOKING_DAYS.keys.freeze

  # Libellés français des jours de la semaine, indexés par wday.
  WDAY_LABELS = {
    0 => "dimanche", 1 => "lundi", 2 => "mardi", 3 => "mercredi",
    4 => "jeudi", 5 => "vendredi", 6 => "samedi"
  }.freeze

  has_many :orders, dependent: :restrict_with_error
  has_many :bake_day_artisans, dependent: :destroy
  has_many :baking_artisans, through: :bake_day_artisans, source: :artisan

  validates :baked_on, presence: true, uniqueness: true
  validates :cut_off_at, presence: true

  scope :future, -> { where("baked_on >= ?", Date.current) }
  scope :past, -> { where("baked_on < ?", Date.current) }
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
      .sum("order_items.qty")
  end

  def total_sales_euros
    orders
      .sum(:total_cents) / 100.0
  end

  def oven_capacity_grams
    setting = ProductionSetting.current
    market_day? ? setting.market_day_oven_capacity_grams : setting.oven_capacity_grams
  end

  class << self
    def next_available
      future.ordered.first
    end

    def calculate_cut_off_for(date)
      days_before = COOKING_DAYS[date.wday]
      return nil unless days_before # pas un jour de cuisson

      # Cut-off à 18:00 (Europe/Brussels), days_before jours avant la cuisson.
      cut_off_date = date - days_before.days
      Time.zone.parse("#{cut_off_date} 18:00:00")
    end
  end
end
