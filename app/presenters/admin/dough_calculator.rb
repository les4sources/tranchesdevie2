module Admin
  # Panification d'un lot de lignes de commande : la pâte ventilée par farine,
  # puis farine / eau / sel / levain dérivés des ratios de chaque farine.
  #
  # Extrait de `Admin::BakeDayDashboard` (#194) pour qu'un lot puisse être soit
  # la journée entière — le tableau global, inchangé — soit une fournée. Une
  # seule implémentation du calcul : c'est ce qui garantit que la somme des
  # fournées égale le tableau global quand toutes les lignes sont affectées.
  class DoughCalculator
    attr_reader :order_items

    # `orders_by_id` sert uniquement au détail de survol (numéro et statut de la
    # commande d'origine) ; son absence n'altère aucun total.
    def initialize(order_items, orders_by_id: {})
      @order_items = order_items
      @orders_by_id = orders_by_id
    end

    # Poids total de pâte du lot, en grammes.
    def total_dough_grams
      @total_dough_grams ||= order_items.sum do |item|
        item.qty * (item.product_variant.flour_quantity || 0)
      end
    end

    def flour_type_stats
      @flour_type_stats ||= begin
        flour_stats = Hash.new do |h, flour_id|
          h[flour_id] = { flour: nil, total: 0.0, by_product: Hash.new { |h2, k| h2[k] = { total: 0.0, order_details: [] } } }
        end

        order_items.each do |item|
          order = @orders_by_id[item.order_id]
          variant = item.product_variant
          product = variant.product
          flour_qty_per_unit = variant.flour_quantity || 0
          total_dough = item.qty * flour_qty_per_unit
          next if total_dough.zero?

          product.product_flours.includes(:flour).each do |pf|
            flour = pf.flour
            contribution = total_dough * pf.percentage / 100.0
            flour_stats[flour.id][:flour] = flour
            flour_stats[flour.id][:total] += contribution
            bucket = flour_stats[flour.id][:by_product][product]
            bucket[:total] += contribution
            bucket[:order_details] << {
              order_number: order&.order_number,
              status: order&.status,
              qty: item.qty,
              variant_name: variant.name,
              flour_qty_per_unit: flour_qty_per_unit,
              percentage: pf.percentage,
              contribution: contribution.round
            }
          end
        end

        flour_stats.values
          .select { |stat| stat[:flour].present? && stat[:total].positive? }
          .map do |stat|
            product_details = stat[:by_product].map do |product, data|
              { product: product, flour_quantity: data[:total].round, order_details: data[:order_details] }
            end.select { |detail| detail[:flour_quantity].positive? }
               .sort_by { |detail| detail[:product].name.downcase }

            {
              flour: stat[:flour],
              flour_quantity: stat[:total].round,
              products: product_details
            }
          end
          .sort_by { |stat| [ stat[:flour].position || Float::INFINITY, stat[:flour].name.downcase ] }
      end
    end

    def dough_quantities
      @dough_quantities ||= begin
        # Chaque farine porte son propre ratio de panification (#88), et les
        # QUATRE ingrédients sont des fractions de la PÂTE — décision boulangers
        # du 25/08/2026. Avant, eau et sel se calculaient sur la farine, ce qui
        # mélangeait deux bases dans le même tableau.
        per_flour = flour_type_stats.map do |stat|
          flour = stat[:flour]
          pate_grams = stat[:flour_quantity].to_f

          {
            flour: flour,
            levain_type: flour.levain_type,
            pate_kg:   (pate_grams / 1000.0).round(2),
            farine_kg: (flour.flour_ratio.to_f * pate_grams / 1000.0).round(2),
            sel_kg:    (flour.salt_ratio.to_f * pate_grams / 1000.0).round(3),
            eau_l:     (flour.water_ratio.to_f * pate_grams / 1000.0).round(2),
            levain_kg: (flour.levain_ratio.to_f * pate_grams / 1000.0).round(3)
          }
        end

        totals = {
          pate_kg:   per_flour.sum { |f| f[:pate_kg] }.round(2),
          farine_kg: per_flour.sum { |f| f[:farine_kg] }.round(2),
          sel_kg:    per_flour.sum { |f| f[:sel_kg] }.round(3),
          eau_l:     per_flour.sum { |f| f[:eau_l] }.round(2),
          levain_kg: per_flour.sum { |f| f[:levain_kg] }.round(3)
        }

        # Base technique #83 : deux totaux de levain distincts (froment vs seigle).
        levain_by_type = per_flour.each_with_object(Hash.new(0.0)) do |f, acc|
          acc[f[:levain_type]] += f[:levain_kg]
        end.transform_values { |v| v.round(3) }

        { per_flour: per_flour, totals: totals, levain_by_type: levain_by_type }
      end
    end
  end
end
