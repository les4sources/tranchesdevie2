# frozen_string_literal: true

# Répartit les produits d'un jour de cuisson en fournées, selon les règles que
# Claire a posées le 28/09/2026, par ordre de priorité, précédées d'une
# priorité absolue ajoutée par Michael le 10/10/2026 :
#
#   0. (priorité 1) deux fournées consécutives n'utilisent pas plus de moules
#      d'un type que l'armoire n'en contient (`MoldType#stock`) : pendant
#      qu'une fournée cuit, la suivante lève déjà dans ses moules ;
#   1. faire le moins de fournées possible (65 kg de pain chacune) ;
#   2. garder au maximum une même farine dans une même fournée ;
#   3. passer dans l'ordre petit épeautre, épeautre, seigle, froment ;
#   4. quand une farine doit être coupée, ne pas séparer les produits qui ont
#      le plus d'ingrédients en commun (noix et noix-figues) ;
#   5. puis déborder d'abord avec des produits de 10 kg au plus, glissés dans
#      une fournée d'autres farines ;
#   6. ne couper un produit entre deux fournées qu'en dernier recours ;
#   7. équilibrer les fournées qui ne contiennent qu'une seule et même farine.
#
# La règle 1 fixe le nombre de fournées ; les autres forment un score comparé
# terme à terme dans cet ordre, où la plus petite valeur gagne. La règle 3
# range aussi les fournées dans l'ordre de passage.
#
# La règle 0 s'applique ensuite à la répartition de Claire, seulement si les
# moules manquent : on change d'abord l'ordre de passage, puis on déplace des
# pains d'une fournée à l'autre, en ouvrant une fournée de plus s'il le faut.
# Si c'est impossible (une seule commande dépasse déjà le stock), on garde la
# répartition qui en manque le moins.
#
# Calcul pur, sans base : `BatchProposalService` lui passe les produits pesés et
# classés, puis écrit le résultat. C'est ce qui permet de tester les règles sur
# des poids réalistes sans fabriquer des centaines de commandes.
class BatchPacker
  # Un produit du jour, toutes variantes confondues. `family` est sa farine
  # principale, `rank` son rang dans l'ordre de passage (règle 3), `lines` ses
  # lignes de commande sous la forme [[clé, grammes], …] — l'unité la plus fine
  # qu'on puisse déplacer, puisque c'est la ligne qu'on affecte à une fournée.
  Product = Struct.new(:key, :family, :rank, :ingredients, :lines, keyword_init: true) do
    def grams
      lines.sum(&:last)
    end
  end

  Family = Struct.new(:key, :products, :grams)
  # Une portion de produit posée dans une fournée : le produit entier, ou
  # quelques-unes de ses lignes quand il a fallu le couper (règle 6).
  Part = Struct.new(:product, :bin, :line_keys, :grams)

  # Nombre de nœuds explorés au-delà duquel on garde la meilleure répartition
  # trouvée. Une journée réelle compte une vingtaine de produits et reste très
  # en dessous ; la borne protège seulement le clic d'un cas imprévu.
  SEARCH_BUDGET = 200_000

  # Nombre de fournées jusqu'auquel on essaie tous les ordres de passage pour
  # tenir le stock de moules (5! = 120 ordres). Une journée réelle en a 2 ou 3.
  MAX_REORDERED_BINS = 5

  # `line_molds` : { clé de ligne => [type de moule, unités] } pour les lignes
  # qui occupent un moule ; `mold_stock` : { type de moule => moules en stock }.
  # Sans eux, la règle 0 ne contraint rien.
  def initialize(products, capacity:, small_product_grams:, line_molds: {}, mold_stock: {})
    @products = products
    @capacity = capacity
    @small_product_grams = small_product_grams
    @mold_stock = mold_stock
    @line_molds = line_molds.select { |_, (mold, _)| mold_stock[mold] }
    @explored = 0
  end

  # Fournées dans l'ordre de passage, chacune un Array de clés de lignes.
  def call
    return [] if @products.empty?

    first = [ (@products.sum(&:grams).to_f / @capacity).ceil, 1 ].max
    last = [ @products.sum { |product| product.lines.size }, first ].max

    (first..last).each do |bin_count|
      parts = best_for(bin_count)
      return fit_molds(ordered_bins(parts)) if parts
    end

    # Inatteignable : avec une fournée par ligne, chaque ligne trouve sa place.
    raise "Aucune répartition trouvée"
  end

  private

  # Règle 0, appliquée à la répartition de Claire quand les moules manquent.
  def fit_molds(bins)
    return bins if @line_molds.empty? || mold_overflow(bins).zero?

    bins = reorder_for_molds(bins)
    return bins if mold_overflow(bins).zero?

    balance(move_for_molds(bins))
  end

  # Moules qui manqueraient, tous types confondus, sur chaque paire de
  # fournées qui se suivent (sur la fournée seule quand il n'y en a qu'une).
  def mold_overflow(bins)
    usages = bins.map { |keys| mold_usage(keys) }
    windows = usages.size == 1 ? [ usages ] : usages.each_cons(2).to_a

    windows.sum do |window|
      @mold_stock.sum do |mold, stock|
        [ window.sum { |usage| usage[mold] } - stock, 0 ].max
      end
    end
  end

  def mold_usage(keys)
    keys.each_with_object(Hash.new(0)) do |key, usage|
      mold, units = @line_molds[key]
      usage[mold] += units if mold
    end
  end

  # L'ordre de passage le plus proche de celui de la règle 3 qui manque le
  # moins de moules : deux fournées pleines de petits moules passent de part
  # et d'autre d'une fournée qui en utilise peu, plutôt que de se suivre.
  def reorder_for_molds(bins)
    return bins if bins.size < 3 || bins.size > MAX_REORDERED_BINS

    indexes = bins.each_index.to_a
    best = indexes.permutation.min_by do |order|
      [ mold_overflow(bins.values_at(*order)), indexes.combination(2).count { |a, b| order.index(a) > order.index(b) } ]
    end

    bins.values_at(*best)
  end

  # Déplace des pains, un client à la fois, de la fournée où les moules
  # manquent vers celle qui les absorbe le mieux, ou vers une nouvelle
  # fournée glissée dans l'ordre de passage. À manque égal, on préfère une
  # fournée existante, puis celle qui a déjà ce produit, puis sa farine
  # (règles 1, 2 et 6), puis la plus légère. Chaque déplacement réduit le
  # manque : la boucle s'arrête d'elle-même.
  def move_for_molds(bins)
    bins = bins.map(&:dup)
    overflow = mold_overflow(bins)

    while overflow.positive?
      best = nil

      bins.each_with_index do |keys, from|
        keys.each do |key|
          next unless @line_molds.key?(key)

          targets(bins, from).each do |to, new_bin|
            candidate = moved(bins, key, from, to, new_bin)
            next unless candidate

            rank = [ mold_overflow(candidate), new_bin ? 1 : 0, affinity(bins, key, new_bin ? nil : to), new_bin ? 0 : weight(bins[to]) ]
            best = [ rank, candidate ] if best.nil? || (rank <=> best.first).negative?
          end
        end
      end

      break if best.nil? || best.first.first >= overflow

      overflow = best.first.first
      bins = best.last
    end

    bins
  end

  # Les déplacements pour les moules laissent parfois une fournée de quelques
  # pains à côté d'une fournée pleine. On rapproche les poids (règle 7) en
  # passant des pains de la plus lourde à la plus légère, de préférence ceux
  # dont le produit ou la farine y sont déjà (règle 2), sans jamais manquer de
  # plus de moules.
  def balance(bins)
    overflow = mold_overflow(bins)

    200.times do
      heavy = bins.each_index.max_by { |index| weight(bins[index]) }
      light = bins.each_index.min_by { |index| weight(bins[index]) }
      gap = weight(bins[heavy]) - weight(bins[light])

      candidate = bins[heavy].select { |key| line_grams[key] < gap }
                             .sort_by { |key| [ affinity(bins, key, light), -line_grams[key] ] }
                             .lazy
                             .map { |key| moved(bins, key, heavy, light, false) }
                             .find { |result| result && mold_overflow(result) <= overflow }
      break unless candidate

      bins = candidate
    end

    bins
  end

  # Fournées où une ligne de la fournée `from` peut aller : chacune des
  # autres, et une nouvelle fournée à chaque place de l'ordre de passage.
  def targets(bins, from)
    existing = bins.each_index.reject { |index| index == from }.map { |index| [ index, false ] }
    existing + (0..bins.size).map { |index| [ index, true ] }
  end

  def moved(bins, key, from, to, new_bin)
    grams = line_grams[key]
    return nil if !new_bin && weight(bins[to]) + grams > @capacity

    result = bins.map(&:dup)
    result[from].delete(key)
    new_bin ? result.insert(to, [ key ]) : result[to] << key
    result.reject(&:empty?)
  end

  # 0 si la fournée d'arrivée a déjà ce produit, 1 si elle a sa farine, 2 sinon.
  def affinity(bins, key, to)
    return 2 if to.nil?

    product = product_by_line[key]
    others = bins[to].map { |other| product_by_line[other] }
    return 0 if others.any? { |other| other.key == product.key }
    return 1 if others.any? { |other| other.family == product.family }

    2
  end

  def weight(keys)
    keys.sum { |key| line_grams[key] }
  end

  def product_by_line
    @product_by_line ||= @products.flat_map { |product| product.lines.map { |key, _| [ key, product ] } }.to_h
  end

  def families
    @families ||= @products.group_by(&:family).map do |key, products|
      Family.new(key, products, products.sum(&:grams))
    end
  end

  # Meilleure répartition en `bin_count` fournées, ou nil. On essaie d'abord de
  # garder chaque farine entière, puis en coupant une farine, puis deux… (règle
  # 2) : dès qu'un niveau aboutit, les suivants ne feraient que couper plus.
  def best_for(bin_count)
    forced, free = families.partition { |family| family.grams > @capacity }

    (0..free.size).each do |extra|
      best = nil

      free.combination(extra).each do |chosen|
        split = forced + chosen

        each_whole_layout(families - split, bin_count) do |loads, used, parts|
          place_split(split, loads, used, parts) do |candidate|
            score = score(candidate)
            best = [ score, candidate ] if best.nil? || (score <=> best.first).negative?
          end
        end
      end

      return refine(best.last) if best
    end

    nil
  end

  # Affinage des produits coupés : on déplace leurs lignes une à une entre les
  # fournées où ils sont déjà, tant que le score s'améliore. Les morceaux de
  # même taille ne suffisent pas toujours à équilibrer (règle 7) : 80 kg de
  # froment + 20 kg aux graines donnent 53/47 en trois morceaux, 50/50 ici.
  def refine(parts)
    best = merge_parts(parts)
    best_score = score(best)

    200.times do
      improved = nil

      best.group_by { |part| part.product.key }.each_value do |pieces|
        next if pieces.size < 2

        pieces.each do |from|
          from.line_keys.each do |line_key|
            pieces.each do |to|
              next if to.bin == from.bin
              next if best.select { |part| part.bin == to.bin }.sum(&:grams) + line_grams[line_key] > @capacity

              candidate = move_line(best, from, to, line_key)
              candidate_score = score(candidate)
              improved = [ candidate_score, candidate ] if (candidate_score <=> (improved&.first || best_score)).negative?
            end
          end
        end
      end

      break unless improved

      best_score, best = improved
    end

    best
  end

  # Une portion par produit et par fournée, rattachée au produit d'origine
  # (et non plus à ses morceaux).
  def merge_parts(parts)
    originals = @products.index_by(&:key)

    parts.group_by { |part| [ part.product.key, part.bin ] }.map do |(key, bin), same|
      Part.new(originals[key], bin, same.flat_map(&:line_keys), same.sum(&:grams))
    end
  end

  def move_line(parts, from, to, line_key)
    grams = line_grams[line_key]

    parts.filter_map do |part|
      if part.equal?(from)
        next if part.line_keys.size == 1

        Part.new(part.product, part.bin, part.line_keys - [ line_key ], part.grams - grams)
      elsif part.equal?(to)
        Part.new(part.product, part.bin, part.line_keys + [ line_key ], part.grams + grams)
      else
        part
      end
    end
  end

  def line_grams
    @line_grams ||= @products.flat_map(&:lines).to_h
  end

  # Toutes les façons de poser les farines gardées entières, chacune dans une
  # seule fournée. Les fournées encore vides sont interchangeables : on n'en
  # essaie qu'une, pour ne pas explorer les mêmes répartitions permutées.
  def each_whole_layout(whole, bin_count, &block)
    walk_whole(whole.sort_by { |family| -family.grams }, 0, Array.new(bin_count, 0), Array.new(bin_count, false), [], &block)
  end

  def walk_whole(whole, index, loads, used, parts, &block)
    return yield(loads.dup, used.dup, parts.dup) if index == whole.size

    family = whole[index]
    first_free = used.index(false)

    loads.each_index do |bin|
      next if !used[bin] && bin != first_free
      next if loads[bin] + family.grams > @capacity

      previous = used[bin]
      loads[bin] += family.grams
      used[bin] = true
      family.products.each { |product| parts << Part.new(product, bin, product.lines.map(&:first), product.grams) }

      walk_whole(whole, index + 1, loads, used, parts, &block)

      parts.pop(family.products.size)
      used[bin] = previous
      loads[bin] -= family.grams
    end
  end

  # Pose les produits des farines coupées dans la place qui reste, sans couper
  # aucun produit si c'est possible. Sinon (règle 6), on coupe le plus gros
  # produit en 2, 3 ou 4 morceaux équilibrés, puis les deux plus gros, etc., et
  # on relance la même recherche : le score choisit ensuite le découpage le
  # mieux équilibré (règle 7). Le remplissage ligne à ligne ne sert qu'en tout
  # dernier recours.
  def place_split(split, loads, used, parts, &block)
    products = split.flat_map(&:products)
    return if walk_units(products, loads, used, parts, &block)

    cuttable = products.select { |product| product.lines.size > 1 }.sort_by { |product| -product.grams }
    (1..cuttable.size).each do |count|
      cut = cuttable.first(count)
      found = false

      [ 2, 3, 4 ].each do |pieces|
        units = products.flat_map { |product| cut.include?(product) ? chunks(product, pieces) : [ product ] }
        found = walk_units(units, loads, used, parts, &block) || found
      end

      return if found
    end

    candidate = greedy_split(products.sort_by { |product| -product.grams }, loads.dup, used.dup, parts.dup)
    yield candidate if candidate
  end

  def walk_units(units, loads, used, parts)
    found = false
    walk_split(units.sort_by { |unit| -unit.grams }, 0, loads.dup, used.dup, parts.dup) do |candidate|
      found = true
      yield candidate
    end
    found
  end

  # Coupe un produit en `pieces` morceaux de poids proches, ligne par ligne (la
  # plus lourde d'abord, dans le morceau le plus léger). Les morceaux gardent la
  # clé du produit : le score voit ainsi qu'il a été coupé.
  def chunks(product, pieces)
    groups = Array.new(pieces) { [] }
    product.lines.sort_by { |line| -line.last }.each do |line|
      groups.min_by { |group| group.sum(&:last) } << line
    end

    groups.reject(&:empty?).map do |lines|
      Product.new(key: product.key, family: product.family, rank: product.rank, ingredients: product.ingredients, lines: lines)
    end
  end

  def walk_split(products, index, loads, used, parts, &block)
    return if @explored >= SEARCH_BUDGET

    @explored += 1
    return yield(parts.dup) if index == products.size

    product = products[index]
    first_free = used.index(false)

    loads.each_index do |bin|
      next if !used[bin] && bin != first_free
      next if loads[bin] + product.grams > @capacity

      previous = used[bin]
      loads[bin] += product.grams
      used[bin] = true
      parts << Part.new(product, bin, product.lines.map(&:first), product.grams)

      walk_split(products, index + 1, loads, used, parts, &block)

      parts.pop
      used[bin] = previous
      loads[bin] -= product.grams
    end
  end

  # Dernier recours : chaque produit entier là où il tient, sinon ses lignes
  # une à une, de préférence là où le produit ou sa farine sont déjà. Viser la
  # fournée la plus vide équilibre les poids au passage. Une ligne seule plus
  # lourde qu'une fournée entière prend une fournée vide pour elle.
  def greedy_split(products, loads, used, parts)
    products.each do |product|
      family_bins = parts.select { |part| part.product.family == product.family }.map(&:bin)
      bin = pick_bin(loads, product.grams, family_bins)

      if bin
        add_part(parts, loads, used, product, bin, product.lines)
        next
      end

      product.lines.sort_by { |line| -line.last }.each do |line|
        product_bins = parts.select { |part| part.product.key == product.key }.map(&:bin)
        bin = pick_bin(loads, line.last, product_bins + family_bins) || used.index(false)
        return nil unless bin

        add_part(parts, loads, used, product, bin, [ line ])
      end
    end

    parts
  end

  def pick_bin(loads, grams, preferred)
    fitting = loads.each_index.select { |bin| loads[bin] + grams <= @capacity }
    fitting.min_by { |bin| [ preferred.include?(bin) ? 0 : 1, loads[bin], bin ] }
  end

  def add_part(parts, loads, used, product, bin, lines)
    grams = lines.sum(&:last)
    loads[bin] += grams
    used[bin] = true

    existing = parts.find { |part| part.product.key == product.key && part.bin == bin }
    if existing
      existing.line_keys += lines.map(&:first)
      existing.grams += grams
    else
      parts << Part.new(product, bin, lines.map(&:first), grams)
    end
  end

  # Le score d'une répartition, comparé terme à terme dans l'ordre des règles.
  # Le dernier terme départage les ex æquo : le moins de pâte possible hors de
  # la fournée principale de sa farine.
  def score(parts)
    homes = homes_by_family(parts)
    bins = parts.group_by(&:bin)

    fragments = 0
    spill = 0
    parts.group_by { |part| part.product.family }.each do |family, family_parts|
      per_bin = family_parts.group_by(&:bin)
      fragments += per_bin.size - 1
      spill += family_parts.reject { |part| part.bin == homes[family] }.sum(&:grams)
    end

    [ fragments, order_inversions(parts, homes), rank_spread(bins), ingredient_cut(parts), large_overflow(parts, homes, bins), split_products(parts), imbalance(bins), spill ]
  end

  # Règle 3 : couples de farines passées à contre-sens, une farine plus loin
  # dans l'ordre sortant avant une farine qui devrait la précéder. Sans ce
  # terme, « petit épeautre + froment, puis épeautre » vaudrait « petit
  # épeautre + épeautre, puis froment ».
  def order_inversions(parts, homes)
    ranks = parts.group_by(&:bin).transform_values { |bin_parts| bin_parts.map { |part| part.product.rank }.uniq }
    order = bin_order(parts, homes)

    order.each_with_index.sum do |earlier, index|
      order.drop(index + 1).sum do |later|
        ranks[earlier].sum { |early| ranks[later].count { |late| early > late } }
      end
    end
  end

  # Règle 3, suite : des farines voisines dans l'ordre de passage partagent une
  # fournée plutôt que des farines éloignées. Petit épeautre + épeautre, puis
  # froment — et non petit épeautre, puis épeautre + froment (23/06/2026 : 9,75
  # + 22,55 + 44,3 kg, les deux découpes faisaient jeu égal sans ce terme).
  def rank_spread(bins)
    bins.values.sum do |bin_parts|
      ranks = bin_parts.map { |part| part.product.rank }
      ranks.max - ranks.min
    end
  end

  # Fournée principale de chaque farine : celle qui en porte le plus.
  def homes_by_family(parts)
    parts.group_by { |part| part.product.family }.transform_values do |family_parts|
      family_parts.group_by(&:bin)
                  .max_by { |bin, bin_parts| [ bin_parts.sum(&:grams), -bin ] }
                  .first
    end
  end

  # Règle 4 : ingrédients communs entre produits d'une même farine qui ne
  # partent pas dans la même fournée.
  def ingredient_cut(parts)
    main_bins = parts.group_by { |part| part.product.key }.transform_values do |product_parts|
      product_parts.group_by(&:bin).max_by { |bin, bin_parts| [ bin_parts.sum(&:grams), -bin ] }.first
    end

    @products.group_by(&:family).values.sum do |products|
      products.combination(2).sum do |a, b|
        next 0 if main_bins[a.key] == main_bins[b.key]

        (a.ingredients & b.ingredients).size
      end
    end
  end

  # Règle 5 : produits de plus de 10 kg partis hors de la fournée principale de
  # leur farine, dans une fournée qui contient d'autres farines.
  def large_overflow(parts, homes, bins)
    parts.count do |part|
      family = part.product.family
      next false if part.bin == homes[family]
      next false if part.product.grams <= @small_product_grams

      bins[part.bin].any? { |other| other.product.family != family }
    end
  end

  # Règle 6 : produits coupés entre plusieurs fournées.
  def split_products(parts)
    parts.group_by { |part| part.product.key }.count { |_, product_parts| product_parts.map(&:bin).uniq.size > 1 }
  end

  # Règle 7 : écart de poids entre fournées d'une seule et même farine.
  def imbalance(bins)
    pure = Hash.new { |hash, key| hash[key] = [] }
    bins.each_value do |bin_parts|
      families = bin_parts.map { |part| part.product.family }.uniq
      pure[families.first] << bin_parts.sum(&:grams) if families.size == 1
    end

    pure.values.sum { |weights| weights.size > 1 ? weights.max - weights.min : 0 }
  end

  # Règle 3 : une fournée passe au rang de la farine dont elle est la fournée
  # principale (à défaut, de sa farine la mieux placée). À rang égal, la plus
  # lourde d'abord.
  def ordered_bins(parts)
    bins = parts.group_by(&:bin)

    bin_order(parts, homes_by_family(parts)).map do |bin|
      bins[bin].sort_by { |part| [ part.product.rank, -part.grams ] }.flat_map(&:line_keys)
    end
  end

  def bin_order(parts, homes)
    parts.group_by(&:bin)
         .sort_by do |bin, bin_parts|
           home_ranks = bin_parts.select { |part| homes[part.product.family] == bin }.map { |part| part.product.rank }
           ranks = home_ranks.presence || bin_parts.map { |part| part.product.rank }
           [ ranks.min, -bin_parts.sum(&:grams), bin ]
         end
         .map(&:first)
  end
end
