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

  def order_payment_method_label(method)
    labels = {
      stripe: "Carte / Bancontact",
      wallet: "Portefeuille"
    }

    labels[method&.to_sym]
  end

  # Petite icône SVG (style heroicons) indiquant le mode d'encaissement réel.
  CARD_ICON_PATH = "M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 0 0 " \
                   "2.25-2.25V6.75A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25v10.5A2.25 " \
                   "2.25 0 0 0 4.5 19.5Z".freeze
  WALLET_ICON_PATH = "M21 12a2.25 2.25 0 0 0-2.25-2.25H15a3 3 0 1 1-6 0H5.25A2.25 2.25 0 0 0 3 12m18 0v6a2.25 " \
                     "2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 18v-6m18 0V9M3 12V9m18 0a2.25 2.25 0 0 " \
                     "0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 9m18 0V6a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 6v3".freeze

  def order_payment_method_icon(order)
    label, path = case order.payment_method
    when :stripe then [ "Payé par carte", CARD_ICON_PATH ]
    when :wallet then [ "Payé via le portefeuille", WALLET_ICON_PATH ]
    end
    return unless path

    tag.svg(
      tag.title(label) + tag.path(nil, "stroke-linecap": "round", "stroke-linejoin": "round", d: path),
      xmlns: "http://www.w3.org/2000/svg", fill: "none", viewBox: "0 0 24 24",
      "stroke-width": "1.5", stroke: "currentColor",
      class: "w-5 h-5 text-gray-500 shrink-0", role: "img", "aria-label": label
    )
  end
end
