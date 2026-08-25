module Admin
  # Événements party PUBLICS (#pizza-parties) : la boulangerie les organise à des
  # dates précises ; les clients s'y inscrivent. Les parties PRIVÉES ne sont pas
  # créées ici (elles naissent d'une réservation client) — on les liste en
  # lecture pour l'exploitation.
  class PartyEventsController < Admin::BaseController
    before_action :set_event, only: [ :show, :edit, :update, :destroy ]

    def index
      @public_events = PartyEvent.public_events.upcoming
      @past_public_events = PartyEvent.public_events.past
      @private_events = PartyEvent.private_events.upcoming
                                  .includes(orders: [ :customer, { order_items: { product_variant: :product } } ])
    end

    # Fiche d'un événement (#173). Les deux familles n'ont rien à montrer en
    # commun — une publique se lit par ses inscriptions, une privée par sa
    # commande unique — d'où deux gabarits distincts derrière la même route.
    def show
      # Les commandes annulées restent affichées, avec leur statut : les cacher
      # ferait disparaître une réservation dont l'équipe se souvient. Elles sont
      # en revanche exclues des totaux, comme dans `seats_taken`.
      @orders = @event.orders
                      .includes(:customer, order_items: { product_variant: :product })
                      .order(:created_at)
                      .to_a
      @active_orders = @orders.reject(&:cancelled?)

      if @event.kind_private_party?
        # Une party privée naît d'une réservation unique ; on prend la plus
        # récente non annulée, à défaut la dernière connue.
        @reservation = @active_orders.last || @orders.last
        render :show_private
      else
        render :show_public
      end
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
            .permit(:title, :held_on, :slot, :capacity, :description, :registration_closes_at, :active,
                    :historical_source, :historical_adults, :historical_children, :historical_sourciers, :historical_fees_euros)
    end
  end
end
