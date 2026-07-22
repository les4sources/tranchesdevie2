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

  # `party` (#pizza-parties) : commande issue d'un événement party (privé/public),
  # datée par son `party_event`, SANS fournée.
  enum :source, { checkout: 0, calendar: 1, admin: 2, party: 3 }

  belongs_to :customer
  # Optionnel : une commande party n'a pas de fournée (elle porte un party_event).
  belongs_to :bake_day, optional: true
  belongs_to :party_event, optional: true
  # Un événement party PRIVÉ naît de la réservation du client : si sa commande
  # disparaît (échec Stripe, paiement abandonné expiré), l'événement orphelin ne
  # doit pas continuer à consommer la capacité du créneau (#pizza-parties).
  after_destroy :release_orphaned_private_party_event
  belongs_to :pickup_location
  has_many :order_items, dependent: :destroy
  has_many :wallet_transactions
  has_one :payment, dependent: :destroy
  has_many :invoice_orders, dependent: :destroy
  has_many :invoices, through: :invoice_orders

  validates :total_cents, presence: true, numericality: { greater_than: 0 }
  validates :public_token, presence: true, uniqueness: true
  validates :order_number, presence: true, uniqueness: true
  validates :status, presence: true
  validates :requires_invoice, inclusion: { in: [ true, false ] }
  validate :pickup_location_open_on_bake_day
  validate :bake_day_or_party_event

  COMPLETED_STATUSES = %w[paid ready picked_up].freeze

  before_validation :generate_public_token, on: :create
  before_validation :generate_order_number, on: :create
  before_validation :assign_default_pickup_location, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :by_bake_day, ->(bake_day) { where(bake_day: bake_day) }
  scope :completed, -> { where(status: COMPLETED_STATUSES) }
  scope :ready_unpaid, -> { ready.left_joins(:payment).where(payments: { id: nil }) }
  scope :in_bake_day_range, lambda { |start_date, end_date|
    joins(:bake_day).where(bake_days: { baked_on: start_date..end_date })
  }
  scope :from_calendar, -> { calendar }
  scope :from_checkout, -> { checkout }
  # Commandes affichables dans « Mon compte » (#144) : une commande `pending` est
  # une réservation de capacité transitoire du paiement en ligne (elle devient
  # `paid` ou est supprimée par ExpireStalePendingOrdersJob). Elle ne représente
  # jamais une commande réelle côté client, donc on ne la liste jamais.
  scope :visible_to_customer, -> { where.not(status: :pending) }
  # Commandes logistiquement avancées (prêtes / récupérées / non-récupérées) sans
  # paiement réel : ce sont celles affichées « payé » à tort avant #97
  # (clients à facture, Sémisto, épicerie). Identifiables pour nettoyage.
  scope :marked_paid_without_real_payment, lambda {
    where(status: %w[ready picked_up no_show]).where(payment_status: payment_statuses[:unpaid])
  }

  def total_euros
    (total_cents / 100.0).round(2)
  end

  # Nombre de sacs à pains pour la commande (#52) : 1 sac par unité de pain
  # produit (catégorie « breads » en production maison), pâtons/reventes exclus.
  def bread_bags_count
    order_items.includes(product_variant: :product).sum do |item|
      item.product_variant.product.incurs_bag_cost? ? item.qty : 0
    end
  end

  # Coût total des sacs à pains de la commande à une date donnée (par défaut le
  # jour de cuisson). `nb_sacs × prix_du_sac(à la date)`. Exposé pour le calcul
  # des bénéfices (#54). Si aucun prix de sac n'est défini à la date, le coût
  # est nul (aucune déduction).
  def bread_bags_cost_cents(on: bake_day&.baked_on || Date.current)
    price_cents = BreadBagPrice.amount_cents_on(on) || 0
    bread_bags_count * price_cents
  end

  def can_be_cancelled_by_customer?
    !bake_day.cut_off_passed? && (paid? || unpaid?)
  end

  # Le client peut confirmer lui-même le retrait d'une commande prête (#compte).
  def can_be_picked_up_by_customer?
    ready?
  end

  def unpaid_ready?
    ready? && payment.nil?
  end

  # Le paiement est considéré comme encaissé UNIQUEMENT s'il y a eu un paiement
  # réel (Stripe / portefeuille) ou un marquage explicite admin — jamais par le
  # simple passage logistique à « prêt » (#97). S'appuie sur `payment_status`
  # (#41), qui est synchronisé depuis les transactions réelles et n'est jamais
  # positionné par une transition de statut.
  def payment_received?
    payment_status_paid?
  end

  # Suppression admin : uniquement une commande sans aucun encaissement
  # (`payment_status` unpaid) ni facture émise. Une commande payée se
  # rembourse/annule, elle ne se supprime pas ; une remboursée ou facturée
  # garde son historique.
  def deletable_by_admin?
    payment_status_unpaid? && invoice_status_not_invoiced?
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

  # Recalcule `payment_status` depuis les transactions réelles, en autorisant le
  # retour à "unpaid" — corrige les commandes marquées « payé » à tort (#97).
  # Contrairement à `sync_payment_status!`, peut RÉTROGRADER : à n'utiliser que
  # pour un nettoyage ponctuel (un marquage manuel admin sans transaction serait
  # réinitialisé). Cf. la tâche `orders:resync_payment_status`.
  def recompute_payment_status!
    update_column(:payment_status, self.class.payment_statuses[derived_payment_status])
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

    # Détail ligne à ligne des remboursements de la période (#100), pour le
    # drill-down depuis le total. Même périmètre que `refunds_summary_between`
    # (ventilé par jour de cuisson) pour rester cohérent avec les totaux.
    # Chaque entrée : client, montant remboursé, date du remboursement, commande
    # liée, source (stripe/wallet) et motif si disponible. Trié du plus récent.
    def detailed_refunds_between(start_date, end_date)
      (stripe_refund_details_between(start_date, end_date) +
        wallet_refund_details_between(start_date, end_date))
        .sort_by { |refund| refund[:refunded_at] }
        .reverse
    end

    def stripe_refund_details_between(start_date, end_date)
      in_bake_day_range(start_date, end_date)
        .joins(:payment)
        .merge(Payment.refunded)
        .preload(:customer, :payment)
        .map do |order|
          {
            source: :stripe,
            customer_name: order.customer.full_name,
            amount_cents: order.total_cents,
            refunded_at: order.payment.updated_at,
            order: order,
            reason: nil
          }
        end
    end

    def wallet_refund_details_between(start_date, end_date)
      WalletTransaction.order_refund
        .joins(order: :bake_day)
        .where(bake_days: { baked_on: start_date..end_date })
        .preload(order: :customer)
        .map do |transaction|
          {
            source: :wallet,
            customer_name: transaction.order.customer.full_name,
            amount_cents: transaction.amount_cents,
            refunded_at: transaction.created_at,
            order: transaction.order,
            reason: transaction.description
          }
        end
    end

    # CA NET par produit (#153) : la remise éventuelle de chaque commande est
    # répartie au prorata du poids brut de ses lignes, si bien que la somme du CA
    # par produit se réconcilie EXACTEMENT avec `revenue_between` (net). Le prix
    # brut n'étant pas stocké au net par ligne, on répartit `total_cents` (net)
    # de la commande sur ses lignes (cf. `each_net_order_line`). Trié par CA net.
    def sales_by_product_between(start_date, end_date)
      acc = Hash.new { |hash, key| hash[key] = { name: nil, total_quantity: 0, total_cents: 0 } }

      each_net_order_line(start_date, end_date) do |_order, item, net_cents|
        product = item.product_variant.product
        bucket = acc[product.id]
        bucket[:name] = product.name
        bucket[:total_quantity] += item.qty
        bucket[:total_cents] += net_cents
      end

      acc.values
         .map { |bucket| { product_name: bucket[:name], total_quantity: bucket[:total_quantity], total_cents: bucket[:total_cents] } }
         .sort_by { |entry| -entry[:total_cents] }
    end

    # CA NET par VARIANTE (format) sur la période, avec quantités (#feuille-compta).
    # Même répartition de la remise que `sales_by_product_between` (le net se
    # réconcilie avec `revenue_between`) mais ventilé par variante — chaque format
    # de pain est une ligne distincte, comme dans la feuille compta de Stéphanie.
    # `total_gross_cents` = CA AVANT remise (Σ qty × prix unitaire de la ligne) ;
    # la remise du format = brut − net.
    # Retour : [ { variant:, total_quantity:, total_gross_cents:, total_cents: }, ... ],
    # trié par CA net.
    def sales_by_variant_between(start_date, end_date)
      acc = Hash.new { |hash, key| hash[key] = { variant: nil, total_quantity: 0, total_gross_cents: 0, total_cents: 0 } }

      each_net_order_line(start_date, end_date) do |_order, item, net_cents|
        bucket = acc[item.product_variant_id]
        bucket[:variant] = item.product_variant
        bucket[:total_quantity] += item.qty
        bucket[:total_gross_cents] += item.qty * item.unit_price_cents
        bucket[:total_cents] += net_cents
      end

      acc.values.sort_by { |entry| -entry[:total_cents] }
    end

    # CA NET par catégorie interne (#153). Même répartition de la remise que
    # `sales_by_product_between` : la somme se réconcilie avec `revenue_between`.
    def sales_by_internal_category_between(start_date, end_date)
      acc = Hash.new { |hash, key| hash[key] = { total_quantity: 0, total_cents: 0, order_ids: Set.new } }

      each_net_order_line(start_date, end_date) do |order, item, net_cents|
        category = item.product_variant.product.internal_category
        bucket = acc[category]
        bucket[:total_quantity] += item.qty
        bucket[:total_cents] += net_cents
        bucket[:order_ids] << order.id
      end

      acc.map do |category, bucket|
        {
          internal_category: category,
          orders_count: bucket[:order_ids].size,
          total_quantity: bucket[:total_quantity],
          total_cents: bucket[:total_cents]
        }
      end.sort_by { |entry| -entry[:total_cents] }
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

    private

    # Parcourt chaque ligne des commandes finalisées de la période en fournissant
    # son CA NET (#153). Pour chaque commande, la remise (Σ prix bruts −
    # total_cents) est répartie au prorata du poids brut de ses lignes, en cents
    # entiers dont la somme égale EXACTEMENT le total net de la commande. La
    # ventilation par produit/catégorie se réconcilie donc avec `revenue_between`.
    # Yield : (order, order_item, net_cents_de_la_ligne).
    def each_net_order_line(start_date, end_date)
      completed
        .in_bake_day_range(start_date, end_date)
        .includes(order_items: { product_variant: :product })
        .find_each do |order|
          items = order.order_items.to_a
          next if items.empty?

          gross_line_cents = items.map { |item| item.qty * item.unit_price_cents }
          net_line_cents = distribute_net_cents(gross_line_cents, order.total_cents)

          items.each_with_index do |item, index|
            yield order, item, net_line_cents[index]
          end
        end
    end

    # Répartit `total_cents` (net) sur des lignes au prorata de `weights` (poids
    # bruts), en cents entiers dont la somme égale EXACTEMENT `total_cents`. La
    # dérive d'arrondi (au plus quelques cents) est absorbée par la ligne au poids
    # le plus élevé. Poids tous nuls (commande entièrement offerte) → tout le net
    # est porté par la première ligne (cas dégénéré, reste réconcilié).
    def distribute_net_cents(weights, total_cents)
      return [] if weights.empty?

      weight_sum = weights.sum
      if weight_sum.zero?
        shares = Array.new(weights.size, 0)
        shares[0] = total_cents
        return shares
      end

      shares = weights.map { |weight| (total_cents * weight / weight_sum.to_f).round }
      drift = total_cents - shares.sum
      heaviest_index = weights.each_with_index.max_by { |weight, _| weight }.last
      shares[heaviest_index] += drift
      shares
    end
  end

  # Date de l'événement pour le client : la party est datée par son événement,
  # toute autre commande par sa fournée (#pizza-parties).
  def event_date
    party_event&.held_on || bake_day&.baked_on
  end

  private

  # Toute commande a un point de retrait (#148). Les chemins qui n'en fournissent
  # pas (création admin, reprise d'une commande historique) retombent sur le lieu
  # par défaut de la fournée — « Les 4 Sources » dans les faits.
  def assign_default_pickup_location
    return if pickup_location_id.present?

    open_locations = bake_day ? bake_day.open_pickup_locations.to_a : []
    fallback = open_locations.find(&:default?) || open_locations.first || PickupLocation.default_location

    self.pickup_location_id = fallback&.id
  end

  # Une commande ne peut pas être retirée dans un lieu qui n'est pas ouvert sur
  # sa fournée. Garde-fou serveur : le sélecteur client masque déjà ces lieux,
  # mais une requête forgée ou une page périmée doit être rejetée ici.
  def pickup_location_open_on_bake_day
    return if pickup_location_id.blank? || bake_day.nil?
    return if bake_day.pickup_location_ids.include?(pickup_location_id)

    errors.add(:pickup_location, "n'est pas disponible pour cette fournée")
  end

  # Détruit l'événement privé si cette commande était la dernière à le porter
  # (une réservation privée = un PartyEvent, cf. PartyReservationService).
  def release_orphaned_private_party_event
    return unless party_event&.kind_private_party?
    return if party_event.orders.where.not(id: id).exists?

    party_event.destroy
  end

  # Une commande party est datée par son événement (sans fournée) ; toute autre
  # commande reste rattachée à une fournée (#pizza-parties).
  def bake_day_or_party_event
    if party? || party_event_id.present?
      errors.add(:party_event, "est requis pour une commande party") if party_event_id.nil?
    elsif bake_day_id.nil?
      errors.add(:bake_day, "est requis")
    end
  end

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
