class Order < ApplicationRecord
  enum :status, {
    pending: 0,
    paid: 1,
    ready: 2,
    picked_up: 3,
    no_show: 4,
    cancelled: 5,
    unpaid: 6,
    planned: 7
  }

  # Statut de paiement (axe financier) — distinct du `status` logistique.
  # `prefix: :payment_status` évite la collision de méthodes (`paid?`, `unpaid?`)
  # avec l'enum `status` ci-dessus. `partially_paid` est réservé (non implémenté).
  enum :payment_status, {
    unpaid: 0,
    paid: 1,
    partially_paid: 2,
    refunded: 3
  }, prefix: :payment_status

  # Statut de facturation (axe comptable) — a-t-on émis la facture ?
  enum :invoice_status, {
    not_invoiced: 0,
    invoiced: 1
  }, prefix: :invoice_status

  enum :source, { checkout: 0, calendar: 1, admin: 2 }

  belongs_to :customer
  belongs_to :bake_day
  has_many :order_items, dependent: :destroy
  has_many :wallet_transactions
  has_one :payment, dependent: :destroy

  validates :total_cents, presence: true, numericality: { greater_than: 0 }
  validates :public_token, presence: true, uniqueness: true
  validates :order_number, presence: true, uniqueness: true
  validates :status, presence: true
  validates :requires_invoice, inclusion: { in: [ true, false ] }

  COMPLETED_STATUSES = %w[paid ready picked_up].freeze
  # Statuts qui ne sont atteints qu'une fois le paiement encaissé (Stripe ou portefeuille).
  PAID_STATUSES = %w[paid ready picked_up no_show].freeze

  before_validation :generate_public_token, on: :create
  before_validation :generate_order_number, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :by_bake_day, ->(bake_day) { where(bake_day: bake_day) }
  scope :completed, -> { where(status: COMPLETED_STATUSES) }
  scope :ready_unpaid, -> { ready.left_joins(:payment).where(payments: { id: nil }) }
  scope :in_bake_day_range, lambda { |start_date, end_date|
    joins(:bake_day).where(bake_days: { baked_on: start_date..end_date })
  }
  scope :from_calendar, -> { calendar }
  scope :from_checkout, -> { checkout }

  def total_euros
    (total_cents / 100.0).round(2)
  end

  def can_be_cancelled_by_customer?
    !bake_day.cut_off_passed? && (paid? || unpaid?)
  end

  def unpaid_ready?
    ready? && payment.nil?
  end

  # Le paiement est considéré comme encaissé dès que le statut le sous-entend.
  def payment_received?
    PAID_STATUSES.include?(status)
  end

  def wallet_order_debit
    wallet_transactions.detect { |transaction| transaction.transaction_type == "order_debit" }
  end

  # Méthode d'encaissement réellement enregistrée, indépendamment du statut.
  def payment_method
    return :stripe if payment.present?
    return :wallet if wallet_order_debit.present?

    nil
  end

  def payment_refunded?
    payment&.refunded? ||
      wallet_transactions.any? { |transaction| transaction.transaction_type == "order_refund" }
  end

  # Statut de paiement déduit des transactions RÉELLES (Stripe + portefeuille),
  # indépendamment du `status` logistique. C'est la source de vérité automatique
  # pour `payment_status` (cf. #41) :
  #   - "refunded" si un remboursement réel existe (prime sur le reste) ;
  #   - "paid"     si un encaissement réel existe (Stripe succeeded ou débit wallet) ;
  #   - "unpaid"   sinon.
  def derived_payment_status
    return "refunded" if payment_refunded?
    return "paid" if real_payment_received?

    "unpaid"
  end

  # Recalcule `payment_status` à partir des transactions réelles et le persiste
  # si nécessaire. Appelé automatiquement lorsqu'un paiement ou une transaction
  # de portefeuille est enregistré (cf. Payment / WalletTransaction). Les
  # commandes hors-ligne (cash) sans transaction ne sont jamais touchées ici :
  # le marquage manuel admin reste donc préservé.
  def sync_payment_status!
    new_status = derived_payment_status

    # La synchronisation automatique ne fait que refléter un encaissement ou un
    # remboursement RÉEL. Elle ne repasse jamais à "unpaid" : un marquage manuel
    # admin (paiement hors-ligne cash / client à facture) reste donc préservé.
    return if new_status == "unpaid"
    return if payment_status == new_status

    update_column(:payment_status, self.class.payment_statuses[new_status])
  end

  # Date d'encaissement du paiement.
  # La valeur stockée (saisie manuelle pour les paiements hors-ligne, ou
  # renseignée automatiquement via le webhook Stripe) prime ; à défaut on la
  # déduit de la trace de paiement (paiement Stripe ou débit du portefeuille).
  def paid_at
    read_attribute(:paid_at) || payment&.created_at || wallet_order_debit&.created_at
  end

  def can_transition_to?(new_status)
    case status.to_sym
    when :pending
      new_status.to_sym == :paid
    when :planned
      [ :paid, :cancelled ].include?(new_status.to_sym)
    when :paid
      [ :ready, :cancelled ].include?(new_status.to_sym)
    when :unpaid
      [ :paid, :ready, :cancelled ].include?(new_status.to_sym)
    when :ready
      [ :picked_up, :no_show, :cancelled ].include?(new_status.to_sym)
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

    # Total des commissions Stripe (en cents) prélevées sur les commandes
    # finalisées payées via Stripe sur la période. Les paiements hors Stripe
    # (portefeuille, encaissement manuel) n'ont pas de commission.
    def stripe_fees_between(start_date, end_date)
      completed
        .in_bake_day_range(start_date, end_date)
        .joins(:payment)
        .sum("payments.stripe_fee_cents")
    end

    # Remboursements (Stripe + portefeuille) effectués sur la période, ventilés
    # par jour de cuisson de la commande remboursée — même axe temporel que le CA.
    # Les commandes remboursées (statut `cancelled`) sont déjà exclues du CA via
    # le scope `completed`.
    def refunds_summary_between(start_date, end_date)
      stripe = stripe_refunds_between(start_date, end_date)
      wallet = wallet_refunds_between(start_date, end_date)

      {
        stripe: stripe,
        wallet: wallet,
        count: stripe[:count] + wallet[:count],
        amount_cents: stripe[:amount_cents] + wallet[:amount_cents],
        # Stripe ne rembourse pas sa commission lors d'un remboursement : elle
        # reste donc à la charge de la boulangerie et grève le CA net.
        stripe_fee_cents: stripe[:stripe_fee_cents]
      }
    end

    # Remboursements Stripe : commandes dont le paiement a été remboursé.
    def stripe_refunds_between(start_date, end_date)
      scope = in_bake_day_range(start_date, end_date)
                .joins(:payment)
                .merge(Payment.refunded)

      {
        count: scope.distinct.count(:id),
        amount_cents: scope.sum(:total_cents),
        stripe_fee_cents: scope.sum("payments.stripe_fee_cents")
      }
    end

    # Remboursements portefeuille : transactions de type `order_refund`.
    def wallet_refunds_between(start_date, end_date)
      scope = WalletTransaction.order_refund
                .joins(order: :bake_day)
                .where(bake_days: { baked_on: start_date..end_date })

      {
        count: scope.count,
        amount_cents: scope.sum(:amount_cents)
      }
    end

    def sales_by_product_between(start_date, end_date)
      total_quantity = Arel.sql("SUM(order_items.qty)")
      total_revenue = Arel.sql("SUM(order_items.qty * order_items.unit_price_cents)")

      completed
        .in_bake_day_range(start_date, end_date)
        .joins(order_items: { product_variant: :product })
        .group("products.id", "products.name")
        .order(total_revenue.desc)
        .pluck(
          "products.name",
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

    def sales_by_internal_category_between(start_date, end_date)
      total_quantity = Arel.sql("SUM(order_items.qty)")
      total_revenue = Arel.sql("SUM(order_items.qty * order_items.unit_price_cents)")
      orders_count = Arel.sql("COUNT(DISTINCT orders.id)")

      completed
        .in_bake_day_range(start_date, end_date)
        .joins(order_items: { product_variant: :product })
        .group("products.internal_category")
        .order(total_revenue.desc)
        .pluck(
          "products.internal_category",
          orders_count,
          total_quantity,
          total_revenue
        ).map do |internal_category, orders_count, total_quantity, total_cents|
          {
            # `pluck` renvoie déjà le nom de l'enum (ex. "boulangerie") ; on
            # retombe sur la conversion depuis l'entier au cas où.
            internal_category: Product.internal_categories.key(internal_category) || internal_category.to_s,
            orders_count: orders_count.to_i,
            total_quantity: total_quantity.to_i,
            total_cents: total_cents.to_i
          }
        end
    end

    def top_customers_between(start_date, end_date, limit: 10)
      orders_count = Arel.sql("COUNT(DISTINCT orders.id)")
      total_revenue = Arel.sql("SUM(orders.total_cents)")

      completed
        .in_bake_day_range(start_date, end_date)
        .joins(:customer)
        .group("customers.id", "customers.first_name", "customers.last_name")
        .order(total_revenue.desc)
        .limit(limit)
        .pluck(
          "customers.first_name",
          "customers.last_name",
          orders_count,
          total_revenue
        ).map do |first_name, last_name, orders_count, total_cents|
          {
            customer_name: [ first_name, last_name ].compact.join(" ").strip,
            orders_count: orders_count.to_i,
            total_cents: total_cents.to_i
          }
        end
    end

    def sales_by_weekday_between(start_date, end_date, weekdays)
      completed
        .in_bake_day_range(start_date, end_date)
        .joins(:bake_day)
        .where("EXTRACT(DOW FROM bake_days.baked_on) IN (?)", weekdays)
        .group(Arel.sql("EXTRACT(DOW FROM bake_days.baked_on)"))
        .order(Arel.sql("EXTRACT(DOW FROM bake_days.baked_on)"))
        .pluck(
          Arel.sql("EXTRACT(DOW FROM bake_days.baked_on)::integer"),
          Arel.sql("COUNT(DISTINCT orders.id)"),
          Arel.sql("SUM(orders.total_cents)")
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
          Arel.sql("COUNT(DISTINCT orders.id)"),
          Arel.sql("SUM(orders.total_cents)")
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

  # Encaissement réel (par opposition au `status` logistique) : un paiement
  # Stripe abouti, ou un débit du portefeuille.
  def real_payment_received?
    (payment.present? && payment.succeeded?) ||
      wallet_transactions.any? { |transaction| transaction.transaction_type == "order_debit" }
  end

  def generate_public_token
    return if public_token.present?

    loop do
      # Generate 16 random bytes and convert to integer for Base58 encoding
      bytes = SecureRandom.random_bytes(16)
      # Convert bytes to integer (big-endian, treating as 128-bit number)
      integer = bytes.unpack1("H*").to_i(16)
      self.public_token = Base58.encode(integer)[0..23]
      break unless Order.exists?(public_token: public_token)
    end
  end

  def generate_order_number
    return if order_number.present?

    date_str = Date.current.strftime("%Y%m%d")
    last_order = Order.where("order_number LIKE ?", "TV-#{date_str}-%")
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
