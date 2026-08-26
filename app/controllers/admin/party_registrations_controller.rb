module Admin
  # Inscriptions ajoutées à la main sur une party PUBLIQUE (#203).
  class PartyRegistrationsController < Admin::BaseController
    before_action :set_event
    before_action :set_registration, only: [ :edit, :update, :destroy, :toggle_paid ]

    def new
      @registration = ManualRegistrationForm.new
    end

    def create
      service = build_service(registration_params)

      if service.call
        redirect_to admin_party_event_path(@event), notice: "Inscription ajoutée."
      else
        @registration = ManualRegistrationForm.new(registration_params)
        @errors = service.errors
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      counts = seat_counts(@registration)
      @registration = ManualRegistrationForm.new(
        name: @registration.group_name,
        adults: counts[:adults],
        children: counts[:children],
        paid: @registration.paid?
      )
    end

    def update
      service = build_service(registration_params, order: @registration)

      if service.call
        redirect_to admin_party_event_path(@event), notice: "Inscription modifiée."
      else
        @registration = ManualRegistrationForm.new(registration_params)
        @errors = service.errors
        render :edit, status: :unprocessable_entity
      end
    end

    # Bascule payée / non payée : l'action la plus fréquente, quelqu'un règle
    # sur place après coup.
    def toggle_paid
      ManualPartyRegistrationService.toggle_paid(@registration, paid: !@registration.paid?)

      redirect_to admin_party_event_path(@event),
                  notice: @registration.reload.paid? ? "Inscription marquée payée." : "Inscription marquée non payée."
    end

    def destroy
      @registration.destroy!

      redirect_to admin_party_event_path(@event), notice: "Inscription supprimée."
    end

    private

    # Petit porteur de champs pour le formulaire : l'inscription est une
    # commande, mais le formulaire parle adultes / enfants / payé.
    ManualRegistrationForm = Struct.new(:name, :phone, :email, :adults, :children, :paid, keyword_init: true) do
      FIELDS = %i[name phone email adults children paid].freeze

      # Accepte aussi bien un Hash qu'un ActionController::Parameters déjà
      # permis — d'où le `to_h` avant tout.
      def initialize(attrs = {})
        given = (attrs.respond_to?(:to_h) ? attrs.to_h : attrs).symbolize_keys
        super(**given.slice(*FIELDS))
        self.adults ||= 0
        self.children ||= 0
      end
    end
    helper_method :seat_counts

    def set_event
      @event = PartyEvent.not_deleted.find(params[:party_event_id])
    end

    # Restreint aux inscriptions MANUELLES : on ne modifie pas depuis ici une
    # commande passée en ligne et payée par Stripe.
    def set_registration
      @registration = @event.orders.where(manually_added: true).find(params[:id])
    end

    def build_service(attrs, order: nil)
      ManualPartyRegistrationService.new(
        party_event: @event,
        adults: attrs[:adults],
        children: attrs[:children],
        name: attrs[:name],
        phone: attrs[:phone],
        email: attrs[:email],
        paid: attrs[:paid],
        order: order
      )
    end

    def seat_counts(order)
      helpers.party_seat_counts(order)
    end

    def registration_params
      params.require(:registration).permit(:name, :phone, :email, :adults, :children, :paid)
    end
  end
end
