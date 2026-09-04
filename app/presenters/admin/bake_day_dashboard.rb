module Admin
  class BakeDayDashboard
    attr_reader :bake_day

    def initialize(bake_day)
      @bake_day = bake_day
    end

    def orders
      @orders ||= bake_day.orders
                           .includes({ customer: { groups: :group_product_discounts } },
                                     :pickup_location,
                                     order_items: {
                                       product_variant: [
                                         :mold_type,
                                         { product: { product_images: { image_attachment: :blob }, product_flours: :flour } },
                                         { product_images: { image_attachment: :blob } }
                                       ]
                                     })
                           .order(:created_at)
    end

    def variant_stats
      @variant_stats ||= begin
        grouped = production_order_items.group_by(&:product_variant)

        grouped.map do |variant, items|
          product = variant.product
          order_ids = items.map { |item| item.order_id }.compact.uniq
          {
            variant: variant,
            product: product,
            category: product.category,
            orders_count: order_ids.size,
            units_count: items.sum(&:qty),
            mold_type: variant.mold_type
          }
        end.sort_by { |stat| [ stat[:product].name.downcase, stat[:variant].name.downcase ] }
      end
    end

    def breads_mold_requirements
      @breads_mold_requirements ||= begin
        stats = variant_stats.select { |stat| stat[:product].breads? }

        result = {}
        MoldType.not_deleted.ordered.each do |mt|
          result[mt] = stats.select { |stat| stat[:mold_type]&.id == mt.id }.sum { |stat| stat[:units_count] }
        end

        unassigned = stats.select { |stat| stat[:mold_type].nil? }.sum { |stat| stat[:units_count] }
        result[:unassigned] = unassigned

        result
      end
    end

    def capacity_service
      @capacity_service ||= BakeCapacityService.new(bake_day)
    end

    def kpis
      total_cents = production_orders.sum(&:total_cents)

      {
        orders_count: production_orders.size,
        items_count: production_order_items.sum(&:qty),
        revenue_cents: total_cents,
        variants_count: variant_stats.size,
        open_orders: orders.count { |order| order.pending? || order.unpaid? },
        ready_orders: orders.count { |order| order.ready? || order.picked_up? }
      }
    end

    def customer_breakdown
      @customer_breakdown ||= production_orders.group_by(&:customer).map do |customer, customer_orders|
        # Prix réellement payé par ligne (#drapeaux) : prix public de la variante
        # moins la meilleure remise applicable aux groupes du client. Le service
        # opère sur les groupes préchargés (cf. `orders`), pas de N+1.
        discount_service = GroupDiscountService.new(customer)
        {
          customer: customer,
          orders: customer_orders.map do |order|
            {
              order: order,
              items: order.order_items.map do |item|
                variant = item.product_variant
                {
                  variant: variant,
                  qty: item.qty,
                  paid_unit_cents: variant.price_cents - discount_service.unit_discount_cents(variant)
                }
              end
            }
          end,
          total_cents: customer_orders.sum(&:total_cents),
          statuses: customer_orders.group_by(&:status).transform_values(&:count),
          # Les lieux de retrait du client sur CETTE fournée (#253). Un client
          # peut avoir deux commandes partant à deux endroits : on liste alors
          # les deux sur la même carte plutôt que de scinder le drapeau — un
          # drapeau, c'est un client, et le scinder ferait deux piles pour la
          # même personne. `pickup_location` est préchargé (cf. `orders`), et
          # `compact` couvre la donnée historique sans lieu.
          pickup_locations: customer_orders.map(&:pickup_location).compact.uniq
                                           .sort_by { |location| [ location.position || 0, location.name.to_s.downcase ] }
        }
      end.sort_by { |entry| [ entry[:customer].last_name.to_s.downcase, entry[:customer].first_name.to_s.downcase ] }
    end

    # Répartition par point de retrait (#148) : ce que les boulangers utilisent
    # pour ventiler les produits entre les lieux le jour de la fournée.
    #
    # Renvoie une entrée par lieu OUVERT sur la fournée (même sans commande, pour
    # que l'absence soit explicite), plus tout lieu qui porte des commandes sans
    # être ouvert (cas d'un lieu supprimé depuis) — sans quoi ces commandes
    # disparaîtraient silencieusement du tableau.
    def pickup_location_breakdown
      @pickup_location_breakdown ||= begin
        orders_by_location = production_orders.group_by(&:pickup_location)

        locations = (bake_day.open_pickup_locations.to_a + orders_by_location.keys.compact).uniq

        locations.map do |location|
          location_orders = orders_by_location[location] || []

          {
            pickup_location: location,
            orders: location_orders.sort_by { |order| order.customer.full_name.to_s.downcase },
            orders_count: location_orders.size,
            total_cents: location_orders.sum(&:total_cents),
            variant_stats: variant_stats_for(location_orders)
          }
        end.sort_by { |entry| [ entry[:pickup_location].position || 0, entry[:pickup_location].name.downcase ] }
      end
    end

    def unpaid_orders?
      orders.any?(&:unpaid?)
    end

    def total_flour_quantity
      dough_calculator.total_dough_grams
    end

    # Calculateur de panification du jour ENTIER. Les fournées (#194) en
    # instancient un par lot avec exactement la même classe : les totaux d'une
    # découpe complète retombent donc sur ce tableau global, par construction.
    def dough_calculator
      @dough_calculator ||= DoughCalculator.new(
        production_order_items,
        orders_by_id: (production_orders + party_orders).index_by(&:id)
      )
    end

    def product_flour_stats
      @product_flour_stats ||= begin
        grouped_by_product_id = production_order_items.group_by { |item| item.product_variant.product_id }

        grouped_by_product_id.map do |product_id, items|
          # Get the product from the first item (all items in this group have the same product)
          product = items.first.product_variant.product

          total_flour = items.sum do |item|
            flour_qty = item.product_variant.flour_quantity || 0
            item.qty * flour_qty
          end

          {
            product: product,
            flour_quantity: total_flour
          }
        end.select { |stat| stat[:flour_quantity].positive? }
           .sort_by { |stat| stat[:product].name.downcase }
      end
    end

    def flour_type_stats
      dough_calculator.flour_type_stats
    end

    def dough_quantities
      dough_calculator.dough_quantities
    end

    def ingredient_stats
      @ingredient_stats ||= begin
        items = production_order_items

        ingredient_totals = Hash.new { |h, k| h[k] = { ingredient: nil, total: BigDecimal("0") } }

        items.each do |item|
          variant = item.product_variant
          variant.variant_ingredients.includes(:ingredient).each do |vi|
            ingredient = vi.ingredient
            ingredient_totals[ingredient.id][:ingredient] = ingredient
            ingredient_totals[ingredient.id][:total] += vi.quantity * item.qty
          end
        end

        ingredient_totals.values
          .select { |stat| stat[:total].positive? }
          .sort_by { |stat| stat[:ingredient].name.downcase }
      end
    end

    # Parties dont les pâtons se pétrissent sur CETTE fournée, avec de quoi les
    # annoncer aux boulangers : date, créneau, nombre de pâtons, client.
    #
    # Privées ET publiques (#202) : les deux demandent des pâtons en plus des
    # pains, et le boulanger qui ouvre sa journée doit voir les deux. Elles
    # restent distinguées par `private`, parce qu'elles ne s'organisent pas
    # pareil. La sélection vient de `party_orders`, qui applique déjà
    # `PartyEvent#preparation_bake_day` : une party de midi apparaît donc sur la
    # fournée qui la prépare, pas sur celle du jour où elle a lieu.
    def parties_to_prepare
      @parties_to_prepare ||= party_orders
        .select { |order| order.party_event.present? }
        .sort_by { |order| [ order.party_event.held_on, order.party_event.slot.to_s ] }
        .map { |order| party_entry(order) }
    end

    # Les mêmes parties, indexées par commande : le flux des commandes s'en sert
    # pour poser le badge à côté du nom du client.
    def party_entry_by_order_id
      @party_entry_by_order_id ||= parties_to_prepare.index_by { |entry| entry[:order].id }
    end

    # Flux du jour : les commandes de pain de la fournée ET les commandes party
    # qu'elle prépare, dans l'ordre d'arrivée. Les party n'ont pas de `bake_day`
    # (par design) : sans cette fusion, elles seraient absentes de la seule liste
    # où les boulangers lisent « qui a commandé quoi » (#202).
    def timeline_entries
      @timeline_entries ||= begin
        regular = orders.map { |order| { order: order, party: nil } }
        parties = parties_to_prepare.map { |entry| { order: entry[:order], party: entry } }

        (regular + parties).sort_by { |entry| entry[:order].created_at }
      end
    end

    # Lignes de commande que cette fournée doit produire — commandes du jour
    # ET pâtons des parties pétris ici. C'est l'assiette exacte du tableau
    # global, donc l'assiette exacte que les fournées (#194) se répartissent.
    def production_items
      production_order_items
    end

    def orders_by_id
      @orders_by_id ||= (production_orders + party_orders).index_by(&:id)
    end

    private

    # Récapitulatif agrégé des articles par variante, sur un sous-ensemble de
    # commandes (celles d'un point de retrait). Même forme que `variant_stats`.
    def variant_stats_for(subset_orders)
      subset_orders
        .flat_map(&:order_items)
        .group_by(&:product_variant)
        .map do |variant, items|
          {
            variant: variant,
            product: variant.product,
            units_count: items.sum(&:qty)
          }
        end
        .sort_by { |stat| [ stat[:product].name.downcase, stat[:variant].name.downcase ] }
    end

    PRODUCTION_STATUSES = %i[unpaid paid ready picked_up planned].freeze

    def production_orders
      @production_orders ||= orders.select { |order| PRODUCTION_STATUSES.include?(order.status.to_sym) }
    end

    # Commandes party dont la pâte est pétrie sur CETTE fournée. Elles n'ont pas
    # de fournée (`bake_day: nil` par design) mais comptent dans les quantités de
    # production (farine, pâte, ingrédients), pas dans le CA ni les retraits.
    #
    # Deux règles distinctes, à dessein (#170) :
    #   - PRIVÉE : la fournée de préparation, qui n'est pas toujours celle du
    #     jour même (cf. PartyEvent#preparation_bake_day) — une party de midi se
    #     prépare la fournée d'avant, et un samedi n'a pas de fournée du tout ;
    #   - PUBLIQUE : le jour même, comme avant. Hors périmètre de #170, elles ont
    #     leur propre organisation.
    def party_orders
      @party_orders ||= BakeDayPartyOrders.production(bake_day)
    end

    def party_entry(order)
      event = order.party_event

      {
        order: order,
        party_event: event,
        held_on: event.held_on,
        slot_label: event.slot_label,
        private: event.kind_private_party?,
        kind_label: event.kind_private_party? ? "Party privée" : "Party publique",
        same_day: event.held_on == bake_day.baked_on,
        paton_count: paton_count_for(order),
        customer_name: order.customer&.full_name
      }
    end

    # Une boule par personne. La ligne « forfait » — unique par commande, quel
    # que soit le nombre de convives — n'est pas un pâton.
    def paton_count_for(order)
      order.order_items.sum do |item|
        item.product_variant.product.pizza_party_role_party? ? item.qty : 0
      end
    end

    def production_order_items
      @production_order_items ||= (production_orders + party_orders).flat_map(&:order_items)
    end
  end
end
