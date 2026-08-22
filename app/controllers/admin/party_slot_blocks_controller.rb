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
      if @block.save
        redirect_to admin_party_slot_blocks_path, notice: "Créneau bloqué."
      else
        @blocks = upcoming_blocks
        @capacity = ProductionSetting.current.private_party_slot_capacity
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      PartySlotBlock.find(params[:id]).destroy
      redirect_to admin_party_slot_blocks_path, notice: "Blocage retiré."
    end

    private

    def upcoming_blocks
      PartySlotBlock.where(blocked_on: Date.current..).order(:blocked_on, :slot)
    end

    def block_params
      params.require(:party_slot_block).permit(:blocked_on, :slot, :reason)
    end
  end
end
