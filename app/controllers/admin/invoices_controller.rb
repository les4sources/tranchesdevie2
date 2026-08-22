# Téléchargement des factures PDF depuis l'admin (#38).
#
# Deux entrées :
#   - `order`  : facture d'une seule commande (admin facturation / fiche commande).
#   - `period` : facture mensuelle groupée d'un client pro, regroupée par jour
#                de cuisson (cf. #27), pour un mois donné.
class Admin::InvoicesController < Admin::BaseController
  # GET /admin/factures/commande/:order_id
  def order
    order = Order.find(params[:order_id])
    invoice = InvoiceBuilderService.for_order(order)

    send_invoice_pdf(invoice)
  end

  # GET /admin/factures/periode?customer_id=&month=YYYY-MM
  def period
    customer = Customer.find(params[:customer_id])
    month = parsed_month(params[:month]) || Date.current.beginning_of_month

    invoice = InvoiceBuilderService.for_customer_month(customer: customer, month: month)

    if invoice.nil?
      redirect_to admin_billing_path(month: month.strftime("%Y-%m"), customer_id: customer.id),
        alert: "Aucune commande à facturer pour ce client sur ce mois."
      return
    end

    send_invoice_pdf(invoice)
  end

  private

  def send_invoice_pdf(invoice)
    service = InvoicePdfService.new(invoice)
    send_data service.render,
      filename: service.filename,
      type: "application/pdf",
      disposition: "attachment"
  end

  def parsed_month(value)
    return nil if value.blank?

    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError, TypeError
    nil
  end
end
