# Libellés de l'état d'une demande de Pizza party, côté client (#pizza-parties).
#
# L'état visible n'est porté par aucune colonne : il se DÉRIVE du couple
# (`PartyRequest.state`, `Order.status` / `payment_status`). La demande est
# terminale à `accepted` ; tout ce qui suit — à régler, confirmée, expirée,
# remboursée — se lit sur la commande. C'est ici, et nulle part ailleurs, que la
# correspondance est écrite : un écran qui ment sur l'état est pire qu'un écran
# absent.
module PartyRequestsHelper
  def party_request_state_key(party_request, order = party_request.order)
    case party_request.state.to_sym
    when :pending   then :pending
    when :cancelled then :cancelled_by_customer
    when :expired   then :expired_no_answer
    when :refused
      # Refus d'emblée, ou retrait d'une validation déjà accordée : la présence
      # d'une commande annulée distingue les deux.
      order.present? ? :withdrawn_by_bakery : :refused
    when :accepted
      accepted_state_key(order)
    else
      :pending
    end
  end

  def party_request_state_label(party_request, order = party_request.order)
    {
      pending: "En attente de réponse",
      refused: "Demande refusée",
      cancelled_by_customer: "Demande annulée",
      expired_no_answer: "Demande close",
      withdrawn_by_bakery: "Réservation annulée par la boulangerie",
      awaiting_payment: "Acceptée — à confirmer et régler",
      confirmed: "Réservation confirmée",
      expired_no_payment: "Réservation expirée",
      cancelled_by_customer_before_payment: "Réservation annulée",
      cancelled_by_bakery_refunded: "Réservation annulée par la boulangerie et remboursée",
      refunded: "Réservation annulée et remboursée"
    }.fetch(party_request_state_key(party_request, order), "En attente de réponse")
  end

  def party_request_state_explanation(party_request, order = party_request.order)
    case party_request_state_key(party_request, order)
    when :pending
      deadline = party_request.deadline_at
      if deadline
        "La boulangerie examine ta demande. Tu recevras sa réponse par e-mail avant le #{I18n.l(deadline.to_date, format: :long_with_day)}. Rien ne t'a été débité."
      else
        "La boulangerie examine ta demande et te répondra par e-mail. Rien ne t'a été débité."
      end
    when :refused
      "La boulangerie n'a pas pu retenir cette date. Rien ne t'a été débité — tu peux faire une nouvelle demande pour une autre soirée."
    when :cancelled_by_customer
      "Tu as annulé cette demande. Rien ne t'a été débité."
    when :expired_no_answer
      "Ta demande n'a pas pu être traitée à temps et a été close automatiquement. Rien ne t'a été débité, et nous t'invitons à retenter pour une autre date."
    when :withdrawn_by_bakery
      "La boulangerie a dû annuler cette réservation après l'avoir acceptée. Rien ne t'a été débité."
    when :awaiting_payment
      "C'est accepté ! Il reste à confirmer ton nombre de participants et à régler ta réservation avant le #{I18n.l(order.payment_due_at.in_time_zone("Europe/Brussels"), format: :long)} — passé ce délai, le créneau est rendu."
    when :confirmed
      "Tout est réglé : ta Pizza party est confirmée. À très vite au fournil !"
    when :expired_no_payment
      "Faute de règlement dans les délais, la réservation a expiré et le créneau a été rendu. Rien ne t'a été débité."
    when :cancelled_by_customer_before_payment
      "Tu as annulé cette réservation avant de la régler. Rien ne t'a été débité."
    when :cancelled_by_bakery_refunded
      "La boulangerie a dû annuler cette réservation. Le montant réglé t'a été intégralement remboursé — nous en sommes désolés."
    when :refunded
      "Tu as annulé cette réservation : le montant réglé t'a été intégralement remboursé."
    end
  end

  def party_request_state_classes(party_request, order = party_request.order)
    case party_request_state_key(party_request, order)
    when :confirmed, :awaiting_payment
      "border-sage-200 bg-sage-100 text-ink-700"
    when :pending
      "border-flour-300 bg-flour-50 text-ink-700"
    else
      "border-danger-200 bg-danger-100 text-danger-700"
    end
  end

  private

  def accepted_state_key(order)
    return :awaiting_payment if order.nil?

    if order.paid? || order.ready? || order.picked_up?
      :confirmed
    elsif order.cancelled?
      cancelled_state_key(order)
    else
      :awaiting_payment
    end
  end

  # Quatre issues distinctes pour une réservation annulée. Elles partagent le
  # même état technique (commande annulée) mais pas du tout le même récit :
  # `cancelled_by` est ce qui les sépare.
  def cancelled_state_key(order)
    if order.payment_status_refunded?
      order.cancelled_by == "customer" ? :refunded : :cancelled_by_bakery_refunded
    elsif order.cancelled_by == "customer"
      :cancelled_by_customer_before_payment
    else
      :expired_no_payment
    end
  end
end
