# Téléchargement de la facture PDF du détail d'une commande, depuis l'espace
# client (#38).
#
# Gating strict :
#   - le client doit être connecté (`authenticate_customer!`) ;
#   - il doit être **facturable** (`billable`) — sinon 404 ;
#   - il ne peut télécharger QUE la facture de ses **propres** commandes — une
#     commande d'un autre client renvoie 404.
class Customers::InvoicesController < ApplicationController
  before_action :authenticate_customer!
  before_action :require_billable!

  # GET /customers/factures/commande/:order_id
  def order
    order = current_customer.orders.find_by(id: params[:order_id])
    raise ActiveRecord::RecordNotFound if order.nil?

    invoice = InvoiceBuilderService.for_order(order)
    service = InvoicePdfService.new(invoice)

    send_data service.render,
      filename: service.filename,
      type: "application/pdf",
      disposition: "attachment"
  end

  private

  # Seuls les clients facturables ont accès aux factures PDF depuis l'espace
  # client. Un non-facturable est traité comme une ressource inexistante (404).
  def require_billable!
    raise ActiveRecord::RecordNotFound unless current_customer&.billable?
  end
end
