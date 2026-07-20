module Admin
  # Événements party PUBLICS (#pizza-parties) : la boulangerie les organise à des
  # dates précises ; les clients s'y inscrivent. Les parties PRIVÉES ne sont pas
  # créées ici (elles naissent d'une réservation client) — on les liste en
  # lecture pour l'exploitation.
  class PartyEventsController < Admin::BaseController
    before_action :set_event, only: [ :edit, :update, :destroy ]

    def index
      @public_events = PartyEvent.public_events.upcoming
      @private_events = PartyEvent.private_events.upcoming.includes(:orders)
    end

    def new
      @event = PartyEvent.new(kind: :public_party, held_on: Date.current)
    end

    def create
      @event = PartyEvent.new(event_params.merge(kind: :public_party))
      if @event.save
        redirect_to admin_party_events_path, notice: "Événement public créé."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @event.update(event_params)
        redirect_to admin_party_events_path, notice: "Événement mis à jour."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @event.soft_delete!
      redirect_to admin_party_events_path, notice: "Événement supprimé."
    end

    private

    def set_event
      @event = PartyEvent.find(params[:id])
    end

    def event_params
      params.require(:party_event)
            .permit(:title, :held_on, :slot, :capacity, :description, :registration_closes_at, :active)
    end
  end
end
