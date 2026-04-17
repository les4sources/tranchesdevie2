module ApplicationHelper
  def order_status_label(status)
    labels = {
      "pending" => "En attente",
      "planned" => "Planifiée",
      "unpaid" => "Non payée",
      "paid" => "Payée",
      "ready" => "Prête",
      "picked_up" => "Récupérée",
      "no_show" => "Non reçue",
      "cancelled" => "Annulée"
    }

    labels[status.to_s] || status.to_s.tr("_", " ").capitalize
  end

  def order_source_label(source)
    labels = {
      "checkout" => "Client (en ligne)",
      "calendar" => "Client (calendrier)",
      "admin" => "Admin"
    }

    labels[source.to_s] || source.to_s.capitalize
  end
end
