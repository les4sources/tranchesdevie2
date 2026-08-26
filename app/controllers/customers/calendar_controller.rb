module Customers
  class CalendarController < ApplicationController
    before_action :authenticate_customer!

    def show
      # Fournées à venir, hors production réservée aux boulangers : une fournée
      # posée un jour non ordinaire (marché, commande spéciale) ne doit pas plus
      # apparaître ici que dans la boutique.
      @bake_days = BakeDay.future.visible_to_customers.ordered
      @planned_orders = current_customer.orders
                                        .where(source: :calendar)
                                        .where.not(status: :cancelled)
                                        .includes(:order_items, :bake_day)
                                        .index_by(&:bake_day_id)
      @wallet = current_customer.wallet || current_customer.create_wallet!
      @committed_cents = current_customer.orders.where(status: :planned, source: :calendar).sum(:total_cents)
      @available_balance_cents = @wallet.balance_cents - @committed_cents
      @product_variants = ProductVariant.active
                                       .store_channel
                                       .visible_to_customer(current_customer)
                                       .joins(:product)
                                       .merge(Product.not_deleted.active.store_channel)
                                       .includes(product: { product_images: :image_attachment })
                                       .order("products.category ASC, products.position ASC, products.name ASC")

      # Points de retrait ouverts, par fournée (#148) : la modale d'une date ne
      # propose que les lieux ouverts ce jour-là.
      @pickup_locations_by_bake_day = @bake_days.index_with { |bake_day| bake_day.orderable_pickup_locations.to_a }
      # Pré-remplissage : dernier lieu choisi par le client, à défaut le lieu par
      # défaut. Un lieu devenu inactif (#199) ne se re-propose pas : on retombe
      # sur le défaut, qui est toujours actif par validation.
      last_location = current_customer.last_pickup_location
      last_location = nil unless last_location&.active?
      @preferred_pickup_location = last_location || PickupLocation.default_location
    end

    def mark_intro_seen
      current_customer.update!(calendar_intro_seen_at: Time.current)
      head :no_content
    end

    def update_day
      # Même filtre qu'à l'affichage : un bake_day_id posté à la main ne doit pas
      # ouvrir une fournée réservée aux boulangers.
      bake_day = BakeDay.future.visible_to_customers.find_by(id: params[:bake_day_id])

      unless bake_day
        render json: { error: "Ce jour de cuisson n'est pas disponible." }, status: :unprocessable_entity
        return
      end

      items = params[:items] || []

      if items.empty?
        # Cancel the planned order if exists
        order = current_customer.orders.planned.find_by(bake_day: bake_day, source: :calendar)
        if order
          result = PlannedOrderService.cancel(order: order)
          if result[:error]
            render json: { error: result[:error] }, status: :unprocessable_entity
            return
          end
        end
        render json: { success: true }
      else
        # Create or update the planned order
        result = PlannedOrderService.upsert(
          customer: current_customer,
          bake_day: bake_day,
          items: items.map { |item| item.permit(:product_variant_id, :qty).to_h.symbolize_keys },
          pickup_location: requested_pickup_location
        )

        if result[:error]
          render json: { error: result[:error] }, status: :unprocessable_entity
        else
          render json: {
            success: true,
            order_id: result[:order].id,
            total_cents: result[:order].total_cents,
            pickup_location_id: result[:order].pickup_location_id
          }
        end
      end
    end

    private

    # Point de retrait demandé pour cette date (#148). Absent → nil : le service
    # conserve alors le lieu déjà choisi (ou retombe sur le lieu par défaut à la
    # création). Un lieu inconnu ou supprimé est ignoré ici et rejeté par le
    # service s'il n'est pas ouvert sur la fournée.
    def requested_pickup_location
      id = params[:pickup_location_id]
      return nil if id.blank?

      PickupLocation.not_deleted.find_by(id: id)
    end

    def authenticate_customer!
      unless customer_signed_in?
        respond_to do |format|
          format.html { redirect_to customer_login_path }
          format.json { render json: { error: "Non autorisé" }, status: :unauthorized }
        end
      end
    end
  end
end
