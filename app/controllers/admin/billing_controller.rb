require "csv"

# Facturation mensuelle des clients professionnels (clients `billable`).
# Récapitule, pour un mois donné, les commandes par client pro avec le détail,
# le total et le statut de paiement. Filtrable par mois et par client.
class Admin::BillingController < Admin::BaseController
  include ActionView::Helpers::TextHelper

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

  # Marquage groupé des commandes sélectionnées (#retour Manon).
  #
  # Deux gestes de compta, distincts et indépendants :
  #   - « facturées » / « non facturées » → `invoice_status` (axe comptable) ;
  #   - « payées » → `payment_status` + `paid_at` (axe financier).
  #
  # Le statut logistique (`status`) n'est JAMAIS touché ici : facturer n'est pas
  # cuire, encaisser n'est pas remettre la commande au client.
  def bulk_update
    orders = bulk_scope.where(id: params[:order_ids])

    if orders.empty?
      redirect_back_to_billing(alert: "Aucune commande sélectionnée.")
      return
    end

    notice = apply_bulk_action!(orders)

    if notice
      redirect_back_to_billing(notice: notice)
    else
      redirect_back_to_billing(alert: "Action inconnue.")
    end
  end

  private

  # Périmètre modifiable : uniquement les commandes facturables de clients
  # facturables. Garde-fou serveur — une requête forgée ou une page périmée ne
  # peut pas atteindre une commande hors facturation.
  def bulk_scope
    Order
      .where(status: BillingReportService::BILLABLE_STATUSES)
      .where(customer_id: Customer.billable.select(:id))
  end

  def apply_bulk_action!(orders)
    count = orders.count
    plural = count > 1 ? "s" : ""

    case params[:bulk_action]
    when "mark_invoiced"
      orders.update_all(invoice_status: Order.invoice_statuses[:invoiced], updated_at: Time.current)
      "#{pluralize(count, 'commande')} marquée#{plural} comme facturée#{plural}."
    when "mark_not_invoiced"
      orders.update_all(invoice_status: Order.invoice_statuses[:not_invoiced], updated_at: Time.current)
      "#{pluralize(count, 'commande')} remise#{plural} en « non facturée »."
    when "mark_paid"
      mark_paid!(orders)
      "#{pluralize(count, 'commande')} marquée#{plural} comme payée#{plural}."
    end
  end

  # Encaissement hors ligne (virement du client pro) : on positionne l'axe
  # financier et la date de paiement saisie par Manon. `paid_at` n'écrase pas une
  # date déjà connue (paiement Stripe / portefeuille) — la trace réelle prime.
  def mark_paid!(orders)
    paid_at = bulk_paid_at

    orders.each do |order|
      attributes = { payment_status: :paid }
      attributes[:paid_at] = paid_at if order.read_attribute(:paid_at).blank?
      order.update!(attributes)
    end
  end

  def bulk_paid_at
    raw = params[:paid_at]
    return Time.current if raw.blank?

    Time.zone.parse(raw.to_s) || Time.current
  rescue ArgumentError
    Time.current
  end

  def redirect_back_to_billing(flash_message)
    redirect_to admin_billing_path(
      month: params[:month].presence,
      customer_id: params[:customer_id].presence
    ), flash_message
  end

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
