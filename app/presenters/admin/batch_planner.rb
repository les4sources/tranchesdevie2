module Admin
  # Calculateur de fournées (#194) : la répartition manuelle des lignes du jour
  # en 1 à N enfournements, et ce que chaque fournée demande au pétrin, au four
  # et à l'armoire à moules.
  #
  # Deux invariants tenus ici, et testés :
  #   - aucune répartition automatique n'est calculée, proposée ou appliquée ;
  #   - la somme des fournées égale le tableau global du jour dès que toutes les
  #     lignes sont affectées, parce que les deux passent par `DoughCalculator`.
  class BatchPlanner
    attr_reader :bake_day, :dashboard

    def initialize(bake_day, dashboard = Admin::BakeDayDashboard.new(bake_day))
      @bake_day = bake_day
      @dashboard = dashboard
    end

    def batches
      @batches ||= bake_day.batches.ordered.to_a
    end

    def any_batches?
      batches.any?
    end

    # Une entrée par fournée, dans l'ordre, avec tout ce qui s'affiche sur sa
    # carte : panification, poids de pâte, moules.
    def batch_stats
      @batch_stats ||= batches.map { |batch| stats_for(batch, items_by_batch_id[batch.id] || []) }
    end

    def unassigned_items
      @unassigned_items ||= items_by_batch_id[nil] || []
    end

    def unassigned_lines_count
      unassigned_items.size
    end

    def unassigned_units_count
      unassigned_items.sum(&:qty)
    end

    def assigned_lines_count
      production_items.size - unassigned_lines_count
    end

    def total_lines_count
      production_items.size
    end

    def fully_assigned?
      total_lines_count.positive? && unassigned_lines_count.zero?
    end

    # Lignes groupées par client, pour l'affectation à la main. Chaque client
    # porte son propre bouton « tout le client vers la fournée N ».
    def customer_rows
      @customer_rows ||= production_items
        .group_by { |item| orders_by_id[item.order_id]&.customer }
        .map do |customer, items|
          {
            customer: customer,
            lines: items.map { |item| line_for(item) }
                        .sort_by { |line| [ line[:product].name.downcase, line[:variant].name.downcase ] },
            units_count: items.sum(&:qty),
            order_item_ids: items.map(&:id),
            uniform_batch_id: uniform_batch_id(items)
          }
        end
        .sort_by { |row| customer_sort_key(row[:customer]) }
    end

    # Récapitulatif par variante, pour l'affectation en masse « tous les petits
    # épeautres vers la fournée 2 ». Se combine avec l'affectation par client :
    # les deux écrivent sur les mêmes lignes, la dernière action gagne.
    def variant_rows
      @variant_rows ||= production_items
        .group_by(&:product_variant)
        .map do |variant, items|
          {
            variant: variant,
            product: variant.product,
            units_count: items.sum(&:qty),
            lines_count: items.size,
            order_item_ids: items.map(&:id),
            unassigned_units: items.select { |item| item.batch_id.nil? }.sum(&:qty),
            uniform_batch_id: uniform_batch_id(items)
          }
        end
        .sort_by { |row| [ row[:product].breads? ? 0 : 1, row[:product].name.downcase, row[:variant].name.downcase ] }
    end

    private

    def production_items
      @production_items ||= dashboard.production_items
    end

    def orders_by_id
      @orders_by_id ||= dashboard.orders_by_id
    end

    def items_by_batch_id
      @items_by_batch_id ||= production_items.group_by(&:batch_id)
    end

    # Fournée d'un groupe de lignes, seulement si TOUTES y sont. Trois retours
    # distincts, et la distinction compte : l'id quand le groupe est entier dans
    # une fournée, `nil` quand AUCUNE de ses lignes n'est affectée, et `:mixed`
    # quand il est panaché. Confondre les deux derniers ferait allumer « — » sur
    # un client dont les lignes sont bel et bien réparties.
    def uniform_batch_id(items)
      ids = items.map(&:batch_id).uniq
      return :mixed if ids.size > 1

      ids.first
    end

    def stats_for(batch, items)
      calculator = DoughCalculator.new(items, orders_by_id: orders_by_id)

      {
        batch: batch,
        order_items: items,
        lines_count: items.size,
        units_count: items.sum(&:qty),
        total_dough_grams: calculator.total_dough_grams,
        dough: calculator.dough_quantities,
        molds: mold_breakdown(items)
      }
    end

    # Moules mobilisés par la fournée, par type, avec le détail de ce qui va
    # dedans. Seuls les PAINS occupent un moule : les pâtons de pizza party
    # pèsent sur le pétrin, jamais sur l'armoire — même règle que
    # `BakeCapacityService` (#170).
    def mold_breakdown(items)
      breads = items.select { |item| item.product_variant.product.breads? }
      return [] if breads.empty?

      grouped = breads.group_by { |item| item.product_variant.mold_type }

      typed = MoldType.not_deleted.ordered.filter_map do |mold_type|
        bucket = grouped[mold_type]
        next if bucket.blank?

        { mold_type: mold_type, units_count: bucket.sum(&:qty), details: details_for(bucket) }
      end

      without_mold = grouped[nil]
      return typed if without_mold.blank?

      typed + [ { mold_type: nil, units_count: without_mold.sum(&:qty), details: details_for(without_mold) } ]
    end

    def details_for(items)
      items.group_by(&:product_variant)
           .map { |variant, variant_items| { variant: variant, qty: variant_items.sum(&:qty) } }
           .sort_by { |detail| [ -detail[:qty], detail[:variant].name.downcase ] }
    end

    def line_for(item)
      order = orders_by_id[item.order_id]
      variant = item.product_variant

      {
        order_item: item,
        order: order,
        variant: variant,
        product: variant.product,
        qty: item.qty,
        batch_id: item.batch_id,
        party: order&.source&.to_sym == :party
      }
    end

    # Les commandes party n'ont pas toujours de client nommé ; on les range en
    # fin de liste plutôt que de les faire remonter sur un nom vide.
    def customer_sort_key(customer)
      return [ 1, "", "" ] if customer.nil?

      [ 0, customer.last_name.to_s.downcase, customer.first_name.to_s.downcase ]
    end
  end
end
