# Téléchargement du bon de livraison PDF d'une commande depuis l'admin
# (Facturation), à côté du relevé de commandes.
class Admin::DeliveryNotesController < Admin::BaseController
  # GET /admin/bons-de-livraison/commande/:order_id
  def show
    order = Order.find(params[:order_id])
    unless order.customer.receives_delivery_notes?
      redirect_to admin_billing_path,
        alert: "Ce client n'est pas livré par la boulangerie : pas de bon de livraison."
      return
    end

    service = DeliveryNotePdfService.new(order)

    send_data service.render,
      filename: service.filename,
      type: "application/pdf",
      disposition: "attachment"
  end
end
