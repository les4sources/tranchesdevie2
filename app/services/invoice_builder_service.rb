# Construit et persiste les factures (#38).
#
# Deux modes :
#   - `for_order(order)`          : facture d'une seule commande.
#   - `for_customer_month(...)`   : facture mensuelle groupée d'un client pro,
#                                   couvrant les commandes facturables du mois
#                                   (mêmes statuts que la facturation
#                                   mensuelle, cf. BillingReportService).
#
# La facture est idempotente côté commande unique : si une facture existe déjà
# pour exactement cette commande, on la renvoie au lieu d'en recréer une.
class InvoiceBuilderService
  # Statuts de commande facturables — alignés sur BillingReportService pour
  # rester cohérent avec le récapitulatif mensuel.
  BILLABLE_STATUSES = BillingReportService::BILLABLE_STATUSES

  class << self
    def for_order(order, vat_rate: BakeryDetails.default_vat_rate)
      existing = existing_single_order_invoice(order)
      return existing if existing

      invoice = Invoice.build_for_order(order, vat_rate: vat_rate)
      invoice.save!
      invoice
    end

    # Facture mensuelle groupée pour un client donné, sur le mois contenant
    # `month` (toute date du mois convient). Renvoie nil s'il n'y a aucune
    # commande facturable sur la période.
    def for_customer_month(customer:, month:, vat_rate: BakeryDetails.default_vat_rate)
      period_start = month.beginning_of_month
      period_end = month.end_of_month
      orders = billable_orders_for(customer, period_start, period_end)
      return nil if orders.empty?

      invoice = Invoice.build_for_period(
        customer: customer,
        orders: orders,
        period_start: period_start,
        period_end: period_end,
        vat_rate: vat_rate
      )
      invoice.save!
      invoice
    end

    private

    # Facture déjà émise portant sur exactement cette commande (et elle seule).
    def existing_single_order_invoice(order)
      order.invoices
           .where(period_start: nil, period_end: nil)
           .detect { |invoice| invoice.invoice_orders.size == 1 }
    end

    def billable_orders_for(customer, period_start, period_end)
      Order
        .where(customer_id: customer.id, status: BILLABLE_STATUSES)
        .in_bake_day_range(period_start, period_end)
        .includes(:bake_day, order_items: { product_variant: :product })
        .to_a
        .sort_by { |order| [ order.bake_day.baked_on, order.order_number ] }
    end
  end
end
