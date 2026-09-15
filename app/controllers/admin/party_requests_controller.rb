module Admin
  # File des demandes de Pizza party privée (#pizza-parties).
  #
  # L'écran qui manquait au process : sans lui, une demande n'existe que dans un
  # e-mail, et une réservation validée non payée n'a AUCUN écran — elle est hors
  # de l'index des parties (elle n'est pas une vente) et hors des feuilles de
  # production (elle n'est pas une pâte).
  class PartyRequestsController < Admin::BaseController
    before_action :load_request, only: [ :show, :accept, :refuse, :retract, :update_headcount ]

    def index
      @pending = PartyRequest.awaiting_decision.includes(:customer)
      @awaiting_payment = PartyRequest.awaiting_payment.includes(:customer, order: :party_event)
      # Dates déjà occupées par une party PUBLIQUE : la validation y échouera.
      # Le signaler dans la file évite au boulanger d'aller au clic pour rien.
      @public_party_dates = PartyEvent.public_events.not_deleted
                                      .where(held_on: @pending.map(&:held_on))
                                      .pluck(:held_on).to_set
      @handled = PartyRequest.where(state: [ :refused, :cancelled, :expired ])
                             .includes(:customer)
                             .order(decided_at: :desc, created_at: :desc)
                             .limit(20)
    end

    def show
      @order = @party_request.order
      @conflict = conflicting_public_party
    end

    def accept
      service = PartyDecisionService.new(@party_request, decided_by: decided_by)

      if service.accept
        redirect_to admin_party_request_path(@party_request),
                    notice: "Demande validée. Le client reçoit son lien de règlement."
      else
        redirect_to admin_party_request_path(@party_request), alert: service.errors.to_sentence
      end
    end

    def refuse
      service = PartyDecisionService.new(@party_request, decided_by: decided_by)

      if service.refuse(params[:reason])
        redirect_to admin_party_requests_path, notice: "Demande refusée. Le motif a été envoyé au client."
      else
        redirect_to admin_party_request_path(@party_request), alert: service.errors.to_sentence
      end
    end

    # Correction du nombre de participants par la boulangerie, tant que rien
    # n'est payé — le cas du groupe qui annonce son chiffre au téléphone.
    def update_headcount
      order = @party_request.order

      if order.nil? || !order.awaiting_payment?
        redirect_to admin_party_request_path(@party_request),
                    alert: "Cette réservation n'est plus modifiable."
        return
      end

      service = PartyPaymentService.new(order)

      if service.confirm_headcount!(params[:persons])
        service.sync_payment_intent_amount!
        # Le montant a changé : le client doit le revoir avant de régler.
        order.update_columns(payment_prompted_at: nil)
        PartyRequestNotifier.payment_prompt(order.reload)
        redirect_to admin_party_request_path(@party_request),
                    notice: "Nombre mis à jour. Le client a reçu le nouveau montant."
      else
        redirect_to admin_party_request_path(@party_request), alert: service.errors.to_sentence
      end
    end

    # Retrait d'une validation tant que rien n'est payé.
    def retract
      service = PartyDecisionService.new(@party_request, decided_by: decided_by)

      if service.retract(params[:reason])
        redirect_to admin_party_requests_path, notice: "Réservation annulée. Le client a été prévenu."
      else
        redirect_to admin_party_request_path(@party_request), alert: service.errors.to_sentence
      end
    end

    private

    def load_request
      @party_request = PartyRequest.includes(:customer, party_request_items: { product_variant: :product })
                                   .find(params[:id])
    end

    # Qui a répondu. L'admin n'a pas de comptes nominatifs (mot de passe unique) :
    # le boulanger signe son geste à la main, et c'est cette signature qui part
    # dans « déjà traitée par … ».
    def decided_by
      params[:decided_by].presence || "la boulangerie"
    end

    # Une party publique programmée le même soir rend la validation impossible :
    # on le montre AVANT que le boulanger clique, plutôt que de le laisser
    # buter sur un refus de capacité.
    def conflicting_public_party
      PartyEvent.public_events.not_deleted.find_by(held_on: @party_request.held_on)
    end
  end
end
