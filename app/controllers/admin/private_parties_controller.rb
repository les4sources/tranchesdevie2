module Admin
  # Création à la main d'une pizza party PRIVÉE (#204) : certaines sont
  # demandées par mail ou par téléphone et ne passent jamais par le site.
  class PrivatePartiesController < Admin::BaseController
    before_action :set_event, only: [ :edit, :update, :destroy, :toggle_paid ]
    before_action :load_customers, only: [ :new, :create, :edit, :update ]

    def new
      @form = PrivatePartyForm.new(held_on: Date.current, slot: "soir", persons: 8, forfait: true)
    end

    def create
      service = build_service(private_party_params)

      if service.call
        redirect_to admin_party_event_path(service.party_event), notice: "Pizza party privée créée."
      else
        @form = PrivatePartyForm.new(private_party_params)
        @errors = service.errors
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @form = PrivatePartyForm.new(
        held_on: @event.held_on,
        slot: @event.slot,
        persons: persons_of(@order),
        customer_id: @order&.customer_id,
        name: @order&.group_name,
        forfait: forfait?(@order),
        paid: @order&.paid?
      )
    end

    def update
      service = build_service(private_party_params, party_event: @event)

      if service.call
        redirect_to admin_party_event_path(@event), notice: "Pizza party privée modifiée."
      else
        @form = PrivatePartyForm.new(private_party_params)
        @errors = service.errors
        render :edit, status: :unprocessable_entity
      end
    end

    def toggle_paid
      return head :not_found if @order.nil?

      ManualPrivatePartyService.toggle_paid(@order, paid: !@order.paid?)

      redirect_to admin_party_event_path(@event),
                  notice: @order.reload.paid? ? "Party marquée payée." : "Party marquée non payée."
    end

    # Supprime la party ET sa commande : une party privée créée à la main n'a
    # pas d'existence sans elle.
    def destroy
      @event.orders.destroy_all
      @event.destroy!

      redirect_to admin_party_events_path, notice: "Pizza party privée supprimée."
    end

    private

    PrivatePartyForm = Struct.new(:held_on, :slot, :persons, :customer_id, :name, :phone, :email,
                                  :forfait, :paid, keyword_init: true) do
      FIELDS = %i[held_on slot persons customer_id name phone email forfait paid].freeze

      def initialize(attrs = {})
        given = (attrs.respond_to?(:to_h) ? attrs.to_h : attrs).symbolize_keys
        super(**given.slice(*FIELDS))
        self.persons ||= 1
        self.slot ||= "soir"
      end
    end

    def load_customers
      @customers = Customer.order(:last_name, :first_name)
    end

    def set_event
      @event = PartyEvent.not_deleted.private_events.find(params[:id])
      @order = @event.orders.order(:created_at).last
    end

    def build_service(attrs, party_event: nil)
      ManualPrivatePartyService.new(
        held_on: attrs[:held_on],
        slot: attrs[:slot],
        persons: attrs[:persons],
        customer_id: attrs[:customer_id],
        name: attrs[:name],
        phone: attrs[:phone],
        email: attrs[:email],
        forfait: attrs[:forfait],
        paid: attrs[:paid],
        party_event: party_event
      )
    end

    def persons_of(order)
      return 1 if order.nil?

      order.order_items.sum { |item| item.product_variant.product.pizza_party_role_party? ? item.qty : 0 }
    end

    def forfait?(order)
      return true if order.nil?

      order.order_items.any? { |item| item.product_variant.product.pizza_party_role_forfait? }
    end

    def private_party_params
      params.require(:private_party).permit(:held_on, :slot, :persons, :customer_id, :name, :phone, :email, :forfait, :paid)
    end
  end
end
