module Admin
  # Blocages de créneaux des parties PRIVÉES (#pizza-parties) : le privé est
  # ouvert par défaut ; l'admin bloque ici les créneaux indisponibles.
  class PartySlotBlocksController < Admin::BaseController
    def index
      @blocks = upcoming_blocks
      @block = PartySlotBlock.new(blocked_on: Date.current)
      @capacity = ProductionSetting.current.private_party_slot_capacity
    end

    def create
      @block = PartySlotBlock.new(block_params)

      unless @block.valid?
        @blocks = upcoming_blocks
        @capacity = ProductionSetting.current.private_party_slot_capacity
        return render :index, status: :unprocessable_entity
      end

      @clearance = PartySlotClearance.new(held_on: @block.blocked_on, slot: @block.slot)

      # Bloquer une soirée déjà réservée annule la party de vrais groupes : on
      # les NOMME avant d'agir, et rien ne part tant que le boulanger n'a pas
      # confirmé (#pizza-parties).
      if @clearance.any? && params[:confirmed].blank?
        @impacted = @clearance.impacted
        @pending_requests = @clearance.pending_requests
        # 422 et non 200 : Turbo Drive IGNORE une réponse HTML en 200 sur un
        # POST — l'écran de confirmation ne s'affichait tout simplement pas, et
        # le boulanger croyait son clic sans effet. C'est le statut que Turbo
        # attend pour réafficher un formulaire.
        return render :confirm, status: :unprocessable_entity
      end

      cancelled = 0

      ActiveRecord::Base.transaction do
        @block.save!
        cancelled = @clearance.clear!(reason: cancellation_reason)
      end

      redirect_to admin_party_slot_blocks_path, notice: confirmation_notice(cancelled)
    end

    def destroy
      PartySlotBlock.find(params[:id]).destroy
      redirect_to admin_party_slot_blocks_path, notice: "Blocage retiré."
    end

    private

    def upcoming_blocks
      PartySlotBlock.where(blocked_on: Date.current..).order(:blocked_on, :slot)
    end

    # Motif communiqué aux clients dont la party est annulée. Le boulanger peut
    # l'écrire sur l'écran de confirmation ; à défaut, la raison du blocage.
    def cancellation_reason
      params[:cancellation_reason].presence ||
        @block.reason.presence ||
        "La boulangerie doit fermer cette soirée."
    end

    def confirmation_notice(cancelled)
      return "Créneau bloqué." if cancelled.zero?

      "Créneau bloqué. #{cancelled} réservation#{'s' if cancelled > 1} annulée#{'s' if cancelled > 1}, " \
        "les clients concernés ont été prévenus."
    end

    def block_params
      params.require(:party_slot_block).permit(:blocked_on, :slot, :reason)
    end
  end
end
