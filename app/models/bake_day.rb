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
  has_many :bake_day_pickup_locations, dependent: :destroy
  has_many :pickup_locations, through: :bake_day_pickup_locations
  # Lieux de vente liés à la fournée (#150) : leur coût du jour est déduit de la
  # marge brute avant le partage 70/30. Contrairement aux lieux de RETRAIT, rien
  # n'empêche de décocher un lieu de vente (aucune commande ne s'y rattache) :
  # l'affectation standard `sales_location_ids=` d'ActiveRecord suffit.
  has_many :bake_day_sales_locations, dependent: :destroy
  has_many :sales_locations, through: :bake_day_sales_locations

  validates :baked_on, presence: true, uniqueness: true
  validates :cut_off_at, presence: true
  validate :pickup_locations_in_use_still_open

  after_save :sync_pickup_locations

  scope :future, -> { where("baked_on >= ?", Date.current) }
  scope :past, -> { where("baked_on < ?", Date.current) }
  scope :ordered, -> { order(:baked_on) }

  # Lieux de retrait proposables au client sur cette fournée : les lieux ouverts,
  # non supprimés, dans l'ordre d'affichage.
  def open_pickup_locations
    pickup_locations.not_deleted.ordered
  end

  # Coût total des lieux de vente liés à la fournée (#150), résolu à la date de
  # cuisson (`baked_on`). Chaque lieu contribue le coût de la période qui couvre
  # ce jour (ou 0 s'il n'en a aucune). 0 si aucun lieu n'est lié → neutre.
  def sales_locations_cost_cents(on: baked_on)
    sales_locations.sum { |location| location.cost_cents(on: on) || 0 }
  end

  # Le setter d'ActiveRecord écrirait les jointures IMMÉDIATEMENT, avant même la
  # validation — un lieu déjà commandé serait donc décoché en base avant qu'on
  # puisse le refuser. On met les ids en attente, on valide, puis on applique en
  # `after_save` (cf. `sync_pickup_locations`).
  def pickup_location_ids=(ids)
    @staged_pickup_location_ids = Array(ids).reject(&:blank?).map(&:to_i)
  end

  def pickup_location_ids
    @staged_pickup_location_ids || super
  end

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

  private

  # Ids réellement ouverts en base (indépendamment des ids mis en attente par le
  # formulaire), source de vérité pour détecter un décochage.
  def persisted_pickup_location_ids
    return [] if new_record?

    BakeDayPickupLocation.where(bake_day_id: id).pluck(:pickup_location_id)
  end

  # Refus bloquant : on ne retire pas d'une fournée un lieu auquel des commandes
  # de cette même fournée sont déjà rattachées (elles deviendraient incohérentes).
  def pickup_locations_in_use_still_open
    return if @staged_pickup_location_ids.nil? || new_record?

    removed_ids = persisted_pickup_location_ids - @staged_pickup_location_ids
    return if removed_ids.empty?

    PickupLocation.where(id: removed_ids).each do |location|
      count = orders.where(pickup_location_id: location.id).count
      next if count.zero?

      errors.add(
        :pickup_locations,
        "« #{location.name} » ne peut pas être retiré de cette fournée : " \
        "#{pluralize(count, 'commande y est rattachée', 'commandes y sont rattachées')}."
      )
    end
  end

  # `ActionView::Helpers::TextHelper#pluralize` n'est pas disponible dans un
  # modèle ; on garde la même forme (nombre + libellé accordé) sans l'inclure.
  def pluralize(count, singular, plural)
    "#{count} #{count == 1 ? singular : plural}"
  end

  # Applique les lieux mis en attente (une fois la validation passée), puis
  # garantit qu'à la création le lieu par défaut est toujours ouvert.
  def sync_pickup_locations
    staged = @staged_pickup_location_ids
    @staged_pickup_location_ids = nil

    apply_staged_pickup_locations(staged) if staged
    open_default_pickup_location if saved_change_to_id?

    association(:bake_day_pickup_locations).reset
    association(:pickup_locations).reset
  end

  def apply_staged_pickup_locations(staged_ids)
    scope = BakeDayPickupLocation.where(bake_day_id: id)
    scope.where.not(pickup_location_id: staged_ids).destroy_all

    already_open = BakeDayPickupLocation.where(bake_day_id: id).pluck(:pickup_location_id)
    (staged_ids - already_open).each do |location_id|
      BakeDayPickupLocation.create!(bake_day_id: id, pickup_location_id: location_id)
    end
  end

  # À la création d'une fournée, le lieu par défaut est automatiquement coché.
  def open_default_pickup_location
    default = PickupLocation.default_location
    return unless default

    BakeDayPickupLocation.find_or_create_by!(bake_day_id: id, pickup_location_id: default.id)
  end
end
