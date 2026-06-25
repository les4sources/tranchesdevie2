require "csv"

# Facturation mensuelle des clients professionnels (clients `billable`).
# Récapitule, pour un mois donné, les commandes par client pro avec le détail,
# le total et le statut de paiement. Filtrable par mois et par client.
class Admin::BillingController < Admin::BaseController
  def index
    @month = parsed_month(params[:month]) || Date.current.beginning_of_month
    @customer = Customer.billable.find_by(id: params[:customer_id])
    @billable_customers = Customer.billable.order(:first_name, :last_name)

    @report = BillingReportService.new(month: @month, customer: @customer).call

    respond_to do |format|
      format.html
      format.csv do
        send_data billing_csv(@report),
          filename: "facturation-#{@month.strftime('%Y-%m')}.csv",
          type: "text/csv"
      end
    end
  end

  private

  def parsed_month(value)
    return nil if value.blank?

    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError, TypeError
    nil
  end

  def billing_csv(report)
    CSV.generate(headers: true) do |csv|
      csv << [ "Client", "Date de cuisson", "N° commande", "Articles", "Montant (€)", "Statut paiement", "Date de paiement" ]

      report.customers.each do |billing|
        billing.orders.each do |order|
          csv << [
            billing.customer.full_name,
            I18n.l(order.bake_day.baked_on),
            order.order_number,
            csv_items(order),
            format("%.2f", order.total_cents / 100.0),
            order.payment_received? ? "Payé" : "Impayé",
            order.payment_received? && order.paid_at ? I18n.l(order.paid_at.to_date) : ""
          ]
        end
      end
    end
  end

  def csv_items(order)
    order.order_items.map do |item|
      "#{item.qty}x #{item.full_name}"
    end.join(", ")
  end
end
