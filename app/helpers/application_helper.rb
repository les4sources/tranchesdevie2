module ApplicationHelper
  def order_status_label(status)
    labels = {
      "pending" => "En attente",
      "unpaid" => "Non payée",
      "paid" => "Payée",
      "ready" => "Prête",
      "picked_up" => "Récupérée",
      "no_show" => "Non reçue",
      "cancelled" => "Annulée"
    }

    labels[status.to_s] || status.to_s.tr("_", " ").capitalize
  end
end
