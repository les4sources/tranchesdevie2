# frozen_string_literal: true

# Répartit les produits d'un jour de cuisson en fournées, selon les règles que
# Claire a posées le 28/09/2026, par ordre de priorité :
#
#   1. faire le moins de fournées possible (70 kg de pain chacune) ;
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

  def initialize(products, capacity:, small_product_grams:)
    @products = products
    @capacity = capacity
    @small_product_grams = small_product_grams
    @explored = 0
  end

  # Fournées dans l'ordre de passage, chacune un Array de clés de lignes.
  def call
    return [] if @products.empty?

    first = [ (@products.sum(&:grams).to_f / @capacity).ceil, 1 ].max
    last = [ @products.sum { |product| product.lines.size }, first ].max

    (first..last).each do |bin_count|
      parts = best_for(bin_count)
      return ordered_bins(parts) if parts
    end

    # Inatteignable : avec une fournée par ligne, chaque ligne trouve sa place.
    raise "Aucune répartition trouvée"
  end

  private

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
