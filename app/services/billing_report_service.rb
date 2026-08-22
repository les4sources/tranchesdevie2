# Construit le récapitulatif de facturation mensuelle des clients professionnels
# (clients `billable` : épiceries, points de dépôt, facturés au mois).
#
# Pour un mois donné, regroupe par client les commandes dont le jour de cuisson
# tombe dans le mois, avec le détail des articles, le total, le statut de
# paiement et la date de paiement éventuelle.
#
# Usage :
#   report = BillingReportService.new(month: Date.new(2026, 5, 1)).call
#   report.customers      # => [ CustomerBilling, ... ]
#   report.grand_total_cents
class BillingReportService
  # Statuts de commande pris en compte dans la facturation. On exclut les
  # commandes annulées, planifiées (non confirmées) et en attente de paiement
  # en ligne (pending). `unpaid` est inclus : ce sont précisément les commandes
  # à facturer (impayées).
  BILLABLE_STATUSES = %w[unpaid paid ready picked_up no_show].freeze

  CustomerBilling = Struct.new(
    :customer,
    :orders,
    :total_cents,
    :paid_total_cents,
    :unpaid_total_cents,
    keyword_init: true
  )

  Report = Struct.new(
    :month,
    :customers,
    :grand_total_cents,
    :paid_total_cents,
    :unpaid_total_cents,
    keyword_init: true
  )

  def initialize(month:, customer: nil)
    @month = month.beginning_of_month
    @customer = customer
  end

  def call
    customer_billings = build_customer_billings

    Report.new(
      month: @month,
      customers: customer_billings,
      grand_total_cents: customer_billings.sum(&:total_cents),
      paid_total_cents: customer_billings.sum(&:paid_total_cents),
      unpaid_total_cents: customer_billings.sum(&:unpaid_total_cents)
    )
  end

  private

  def build_customer_billings
    orders_by_customer = scoped_orders.group_by(&:customer_id)

    billable_customers.filter_map do |customer|
      orders = orders_by_customer[customer.id]
      next if orders.blank?

      orders = orders.sort_by { |order| order.bake_day.baked_on }
      paid_cents = orders.select(&:payment_received?).sum(&:total_cents)

      CustomerBilling.new(
        customer: customer,
        orders: orders,
        total_cents: orders.sum(&:total_cents),
        paid_total_cents: paid_cents,
        unpaid_total_cents: orders.sum(&:total_cents) - paid_cents
      )
    end
  end

  def billable_customers
    scope = Customer.billable.order(:first_name, :last_name)
    scope = scope.where(id: @customer.id) if @customer
    scope
  end

  def scoped_orders
    scope = Order
      .where(status: BILLABLE_STATUSES)
      .in_bake_day_range(@month, @month.end_of_month)
      .includes(:bake_day, :payment, order_items: { product_variant: :product })

    scope = scope.where(customer_id: @customer.id) if @customer
    scope
  end
end
