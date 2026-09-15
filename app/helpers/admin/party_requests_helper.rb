module Admin
  # Libellés des demandes de Pizza party côté boulangerie (#pizza-parties).
  module PartyRequestsHelper
    STATE_LABELS = {
      "pending" => "En attente de réponse",
      "accepted" => "Validée",
      "refused" => "Refusée",
      "cancelled" => "Annulée par le client",
      "expired" => "Close sans réponse"
    }.freeze

    def admin_party_request_state_label(party_request)
      STATE_LABELS.fetch(party_request.state.to_s, party_request.state.to_s)
    end

    # Message d'une demande déjà traitée : qui, quand. C'est ce que voit le
    # deuxième boulanger qui ouvre le même lien.
    def admin_party_request_already_handled(party_request)
      base = "Cette demande a déjà été traitée"
      return "#{base}." if party_request.decided_at.blank?

      "#{base} par #{party_request.decided_by} le #{I18n.l(party_request.decided_at, format: :long)}."
    end

    # Nombre de demandes qui attendent une réponse — le badge de la navigation.
    def admin_pending_party_requests_count
      PartyRequest.state_pending.count
    end
  end
end
