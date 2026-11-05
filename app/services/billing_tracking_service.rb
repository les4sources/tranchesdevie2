# Suivi de la facturation et des paiements des clients professionnels sur
# plusieurs mois (#retour Michael) : un tableau croisé clients × mois.
#
# L'écran Facturation sert à PRÉPARER les factures d'un mois. Celui-ci sert à
# VÉRIFIER, d'un coup d'œil, ce qui reste à facturer ou à encaisser sur l'année
# écoulée, sans passer d'un mois à l'autre.
#
# Même assiette que BillingReportService (statuts `COMPLETED_STATUSES`, datés
# par le jour de cuisson, jours brouillon exclus) : le total d'une case est
# exactement celui du mois correspondant dans l'écran Facturation.
#
# Usage :
#   report = BillingTrackingService.new(end_month: Date.new(2026, 11, 1)).call
#   report.months          # => [ 2025-12-01, ..., 2026-11-01 ]
#   report.rows            # => [ Row(customer:, cells: { month => Cell }) ]
#   report.month_totals    # => { month => Cell }
class BillingTrackingService
  DEFAULT_MONTHS = 12

  # Une case du tableau : les commandes d'un client sur un mois, ou un total.
  #
  # Trois sommes, qui se recouvrent :
  #   - `paid_cents`       : encaissé (payment_status paid) ;
  #   - `invoiced_cents`   : facture émise (invoice_status invoiced) ;
  #   - `to_invoice_cents` : ni payé ni facturé — il manque la facture ;
  #   - `awaiting_cents`   : facturé mais pas encore payé — il manque l'argent.
  # Une commande payée en ligne sans facture est réglée : rien à poursuivre.
  # `orders` garde les commandes de la case, pour le détail affiché au clic.
  Cell = Struct.new(
    :orders,
    :orders_count,
    :total_cents,
    :paid_cents,
    :invoiced_cents,
    :to_invoice_cents,
    :awaiting_cents,
    keyword_init: true
  ) do
    def self.empty
      new(orders: [], orders_count: 0, total_cents: 0, paid_cents: 0, invoiced_cents: 0, to_invoice_cents: 0, awaiting_cents: 0)
    end

    def self.from_orders(orders)
      orders.each_with_object(empty) { |order, cell| cell.add_order(order) }
    end

    SUMMED_FIELDS = %i[orders_count total_cents paid_cents invoiced_cents to_invoice_cents awaiting_cents].freeze

    def add_order(order)
      orders << order
      self.orders_count += 1
      self.total_cents += order.total_cents
      paid = order.payment_received?
      invoiced = order.invoice_status_invoiced?
      self.paid_cents += order.total_cents if paid
      self.invoiced_cents += order.total_cents if invoiced
      self.to_invoice_cents += order.total_cents if !paid && !invoiced
      self.awaiting_cents += order.total_cents if !paid && invoiced
      self
    end

    # Un total additionne les sommes, sans recopier les commandes : le détail
    # d'un total se lit client par client.
    def merge!(other)
      SUMMED_FIELDS.each { |field| self[field] += other[field] }
      self
    end

    def unpaid_cents
      total_cents - paid_cents
    end

    def empty?
      orders_count.zero?
    end

    # État dominant de la case, du plus urgent au plus serein :
    #   :empty      — aucune commande ;
    #   :to_invoice — au moins une commande ni facturée ni payée ;
    #   :awaiting   — tout est facturé, une partie attend encore le paiement ;
    #   :paid       — tout est encaissé.
    def state
      return :empty if empty?
      return :to_invoice if to_invoice_cents.positive?
      return :awaiting if awaiting_cents.positive?

      :paid
    end
  end

  Row = Struct.new(:customer, :cells, :total, keyword_init: true)

  Report = Struct.new(:months, :rows, :month_totals, :grand_total, keyword_init: true) do
    def first_month
      months.first
    end

    def last_month
      months.last
    end
  end

  def initialize(end_month: Date.current, months: DEFAULT_MONTHS)
    @end_month = end_month.to_date.beginning_of_month
    @months = (0...months).map { |offset| @end_month << (months - 1 - offset) }
  end

  def call
    orders_by_customer = scoped_orders.group_by(&:customer_id)

    rows = billable_customers.filter_map do |customer|
      orders = orders_by_customer[customer.id]
      next if orders.blank?

      by_month = orders.group_by { |order| order.bake_day.baked_on.beginning_of_month }
      cells = @months.index_with do |month|
        Cell.from_orders((by_month[month] || []).sort_by { |order| order.bake_day.baked_on })
      end
      Row.new(customer: customer, cells: cells, total: sum_cells(cells.values))
    end

    month_totals = @months.index_with { |month| sum_cells(rows.map { |row| row.cells[month] }) }

    Report.new(
      months: @months,
      rows: rows,
      month_totals: month_totals,
      grand_total: sum_cells(month_totals.values)
    )
  end

  private

  def sum_cells(cells)
    cells.each_with_object(Cell.empty) { |cell, total| total.merge!(cell) }
  end

  def billable_customers
    Customer.billable.order(:first_name, :last_name)
  end

  def scoped_orders
    Order
      .where(status: BillingReportService::BILLABLE_STATUSES)
      .where(customer_id: Customer.billable.select(:id))
      .in_bake_day_range(@months.first, @end_month.end_of_month)
      .includes(:bake_day, :payment, :wallet_transactions)
  end
end
