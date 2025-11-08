module ApplicationHelper
  def order_status_label(status)
    labels = {
      "pending" => "En attente",
      "paid" => "Payee",
      "ready" => "Prete",
      "picked_up" => "Recuperee",
      "no_show" => "Non recue",
      "cancelled" => "Annulee"
    }

    labels[status.to_s] || status.to_s.tr("_", " ").capitalize
  end
end
