module Admin
  # Liste des pizza parties PRIVÉES pour l'écran Parties (#205).
  #
  # L'écran partait des `PartyEvent`, le rapport part des COMMANDES : les deux
  # ne voyaient donc pas le même monde. En production le 25/08/2026, sur 18
  # commandes de party privée finalisées, une seule portait un événement — les
  # 17 autres étaient invisibles de l'écran Parties. Et même avec un événement,
  # une party privée disparaissait le lendemain de sa date, faute de section
  # « passées ».
  #
  # On part donc des commandes, comme le rapport, et on affiche l'événement
  # quand il existe. Aucune écriture rétroactive, aucun risque comptable, et
  # l'écran devient cohérent avec le rapport par construction — c'est l'option 2
  # recommandée par l'issue.
  class PrivatePartyIndex
    Entry = Struct.new(:order, :party_event, :held_on, :customer, :paton_count,
                       :total_cents, :forfait, :slot_label, :note, keyword_init: true) do
      def forfait? = forfait
      def event? = party_event.present?
      def total_euros = (total_cents / 100.0).round(2)
    end

    # Commandes portant au moins un pâton de party PRIVÉE, quel que soit leur
    # rattachement : par événement, par fournée, ou aucun des deux.
    def self.orders_scope
      order_ids = OrderItem.joins(product_variant: :product)
                           .where(products: { pizza_party_role: Product.pizza_party_roles[:party] })
                           .select(:order_id)

      Order.where(id: order_ids)
           .includes(:customer, :bake_day, :party_event,
                     order_items: { product_variant: :product })
    end

    def initialize(orders = self.class.orders_scope)
      @orders = orders
    end

    def entries
      @entries ||= @orders
        .reject(&:cancelled?)
        .map { |order| entry_for(order) }
        .sort_by { |entry| [ entry.held_on || Date.new(0), entry.order.created_at ] }
    end

    def upcoming
      entries.select { |entry| entry.held_on.nil? || entry.held_on >= Date.current }
    end

    def past
      entries.select { |entry| entry.held_on.present? && entry.held_on < Date.current }.reverse
    end

    private

    def entry_for(order)
      event = order.party_event

      Entry.new(
        order: order,
        party_event: event,
        # `event_date` couvre les deux rattachements ; nil s'il n'y en a aucun,
        # et on l'affiche tel quel plutôt que d'inventer une date.
        held_on: order.event_date,
        customer: order.customer,
        paton_count: paton_count(order),
        total_cents: order.total_cents,
        forfait: forfait?(order),
        slot_label: event&.slot_label,
        note: order.customer_note
      )
    end

    def paton_count(order)
      order.order_items.sum { |item| item.product_variant.product.pizza_party_role_party? ? item.qty : 0 }
    end

    def forfait?(order)
      order.order_items.any? { |item| item.product_variant.product.pizza_party_role_forfait? }
    end
  end
end
