require "rails_helper"

# Les règles de Claire (28/09/2026) pour proposer une répartition en fournées,
# testées sur des poids réalistes. Calcul pur : aucune donnée en base.
RSpec.describe BatchPacker do
  PETIT_EPEAUTRE = 0
  EPEAUTRE = 1
  FROMENT = 4

  # Un produit dont chaque ligne pèse `line_grams`, pour `total` grammes au
  # total — comme une journée où chaque client prend un ou deux pains.
  def product(key, rank:, kg:, line_grams: 1_000, ingredients: [])
    total = (kg * 1_000).round
    lines = []
    lines << [ "#{key}-#{lines.size}", [ line_grams, total - lines.sum(&:last) ].min ] while lines.sum(&:last) < total

    BatchPacker::Product.new(key: key, family: rank, rank: rank, ingredients: ingredients.to_set, lines: lines)
  end

  # Capacité passée en paramètre : les scénarios ci-dessous sont calibrés à
  # 70 kg et testent les RÈGLES. Le réglage réel (65 kg) vit dans
  # `BatchProposalService::CAPACITY_GRAMS` et se teste dans son spec.
  def pack(*products)
    described_class.new(products, capacity: 70_000, small_product_grams: 10_000).call
  end

  # Chaque fournée ramenée à { produit => kg }, pour des attentes lisibles.
  def contents(bins, products)
    owner = products.flat_map { |product| product.lines.map { |key, grams| [ key, [ product.key, grams ] ] } }.to_h

    bins.map do |keys|
      keys.each_with_object(Hash.new(0)) { |key, acc| acc[owner[key].first] += owner[key].last / 1_000.0 }
    end
  end

  def weights(bins, products)
    contents(bins, products).map { |bin| bin.values.sum }
  end

  it "ne propose rien sans produit" do
    expect(pack).to eq([])
  end

  it "garde une seule fournée jusqu'à 70 kg" do
    products = [ product(:epeautre, rank: EPEAUTRE, kg: 30), product(:froment, rank: FROMENT, kg: 40) ]

    expect(contents(pack(*products), products)).to eq([ { epeautre: 30.0, froment: 40.0 } ])
  end

  it "sépare les farines dès que 70 kg sont dépassés, épeautres d'abord (règles 1 à 3)" do
    products = [
      product(:froment, rank: FROMENT, kg: 60),
      product(:petit_epeautre, rank: PETIT_EPEAUTRE, kg: 10),
      product(:epeautre, rank: EPEAUTRE, kg: 25)
    ]

    expect(contents(pack(*products), products)).to eq([
      { petit_epeautre: 10.0, epeautre: 25.0 },
      { froment: 60.0 }
    ])
  end

  it "met l'épeautre avec le petit épeautre plutôt qu'avec le froment (règle 3, journée du 23/06/2026)" do
    products = [
      product(:petit_epeautre, rank: PETIT_EPEAUTRE, kg: 9.75),
      product(:epeautre, rank: EPEAUTRE, kg: 22.55),
      product(:froment, rank: FROMENT, kg: 44.3)
    ]

    expect(contents(pack(*products), products)).to eq([
      { petit_epeautre: 9.75, epeautre: 22.55 },
      { froment: 44.3 }
    ])
  end

  describe "quand le froment ne tient pas dans une seule fournée" do
    let(:products) do
      [
        product(:petit_epeautre, rank: PETIT_EPEAUTRE, kg: 10),
        product(:epeautre, rank: EPEAUTRE, kg: 25),
        product(:pain_froment, rank: FROMENT, kg: 55),
        product(:graines, rank: FROMENT, kg: 12, ingredients: [ :graines ]),
        product(:noix, rank: FROMENT, kg: 9, ingredients: [ :noix ]),
        product(:noix_figues, rank: FROMENT, kg: 6, ingredients: [ :noix, :figues ]),
        product(:chocolat, rank: FROMENT, kg: 8, ingredients: [ :chocolat, :sucre ])
      ]
    end

    subject(:bins) { contents(pack(*products), products) }

    it "reste à deux fournées de 70 kg au plus (règle 1)" do
      expect(bins.size).to eq(2)
      expect(bins.map { |bin| bin.values.sum }).to all(be <= 70.0)
    end

    it "déborde avec des produits de 10 kg au plus dans la fournée des épeautres (règle 5)" do
      expect(bins.first.keys).to include(:petit_epeautre, :epeautre)
      expect(bins.first.keys).not_to include(:pain_froment, :graines)
    end

    it "garde noix et noix-figues ensemble (règle 4)" do
      noix_bin = bins.index { |bin| bin.key?(:noix) }
      expect(bins[noix_bin]).to have_key(:noix_figues)
    end

    it "ne coupe aucun produit (règle 6)" do
      products.each do |product|
        expect(bins.count { |bin| bin.key?(product.key) }).to eq(1), "#{product.key} coupé"
      end
    end
  end

  it "préfère les produits aux ingrédients communs ensemble plutôt qu'un débord plus léger (règle 4)" do
    products = [
      product(:epeautre, rank: EPEAUTRE, kg: 50),
      product(:pain_froment, rank: FROMENT, kg: 60),
      product(:noix, rank: FROMENT, kg: 6, ingredients: [ :noix ]),
      product(:noix_figues, rank: FROMENT, kg: 6, ingredients: [ :noix, :figues ]),
      product(:chocolat, rank: FROMENT, kg: 7, ingredients: [ :chocolat ])
    ]

    bins = contents(pack(*products), products)

    expect(bins.index { |bin| bin.key?(:noix) }).to eq(bins.index { |bin| bin.key?(:noix_figues) })
  end

  it "équilibre les fournées d'une seule et même farine (règle 7)" do
    products = [ product(:pain_froment, rank: FROMENT, kg: 80), product(:graines, rank: FROMENT, kg: 20, ingredients: [ :graines ]) ]

    expect(weights(pack(*products), products)).to eq([ 50.0, 50.0 ])
  end

  it "coupe un produit trop lourd pour une fournée, en restant au minimum de fournées (règles 1 et 6)" do
    products = [
      product(:pain_froment, rank: FROMENT, kg: 100),
      product(:noix, rank: FROMENT, kg: 30, ingredients: [ :noix ]),
      product(:graines, rank: FROMENT, kg: 20, ingredients: [ :graines ])
    ]

    result = weights(pack(*products), products)

    expect(result.size).to eq(3)
    expect(result).to all(be <= 70.0)
    expect(result.max - result.min).to be <= 2.0
  end

  it "ouvre une fournée de plus plutôt que de dépasser 70 kg quand rien ne s'emboîte" do
    products = [
      product(:epeautre, rank: EPEAUTRE, kg: 40, line_grams: 40_000),
      product(:froment, rank: FROMENT, kg: 40, line_grams: 40_000)
    ]

    expect(weights(pack(*products), products)).to eq([ 40.0, 40.0 ])
  end

  describe "stock de moules sur deux fournées consécutives (priorité 1)" do
    # Un pain par ligne, chacun dans un moule `mold`.
    def molds_of(*products, mold:)
      products.flat_map { |product| product.lines.map { |key, _| [ key, [ mold, 1 ] ] } }.to_h
    end

    def pack_with_molds(products, line_molds:, mold_stock:)
      described_class.new(products, capacity: 70_000, small_product_grams: 10_000, line_molds: line_molds, mold_stock: mold_stock).call
    end

    # Moules utilisés par chaque paire de fournées qui se suivent.
    def pair_usage(bins, line_molds, mold)
      per_bin = bins.map { |keys| keys.sum { |key| line_molds[key]&.first == mold ? line_molds[key].last : 0 } }
      per_bin.each_cons(2).map(&:sum)
    end

    it "ajoute une fournée plutôt que de manquer de petits moules" do
      products = [
        product(:epeautre, rank: EPEAUTRE, kg: 30, line_grams: 600),
        product(:froment, rank: FROMENT, kg: 45, line_grams: 600)
      ]
      line_molds = molds_of(*products, mold: :petit)

      # Sans la contrainte : deux fournées, 125 petits moules à la suite.
      expect(pack(*products).size).to eq(2)

      bins = pack_with_molds(products, line_molds: line_molds, mold_stock: { petit: 80 })

      expect(bins.size).to eq(3)
      expect(pair_usage(bins, line_molds, :petit)).to all(be <= 80)
      expect(weights(bins, products)).to all(be <= 70.0)
      expect(bins.flatten).to match_array(products.flat_map { |product| product.lines.map(&:first) })
    end

    it "change l'ordre de passage quand il suffit à tenir le stock" do
      products = [
        product(:petit_epeautre, rank: PETIT_EPEAUTRE, kg: 42, line_grams: 600),
        product(:epeautre, rank: EPEAUTRE, kg: 42, line_grams: 600),
        product(:froment, rank: FROMENT, kg: 60)
      ]
      line_molds = molds_of(products[0], products[1], mold: :petit).merge(molds_of(products[2], mold: :grand))

      bins = pack_with_molds(products, line_molds: line_molds, mold_stock: { petit: 100, grand: 95 })

      expect(contents(bins, products).map(&:keys)).to eq([ [ :petit_epeautre ], [ :froment ], [ :epeautre ] ])
    end

    it "ne change rien quand le stock suffit" do
      products = [
        product(:froment, rank: FROMENT, kg: 60),
        product(:petit_epeautre, rank: PETIT_EPEAUTRE, kg: 10),
        product(:epeautre, rank: EPEAUTRE, kg: 25)
      ]
      line_molds = molds_of(*products, mold: :grand)

      expect(pack_with_molds(products, line_molds: line_molds, mold_stock: { grand: 95 })).to eq(pack(*products))
    end

    it "ignore les types de moules sans stock renseigné" do
      products = [
        product(:epeautre, rank: EPEAUTRE, kg: 30, line_grams: 600),
        product(:froment, rank: FROMENT, kg: 45, line_grams: 600)
      ]

      bins = pack_with_molds(products, line_molds: molds_of(*products, mold: :petit), mold_stock: {})

      expect(bins).to eq(pack(*products))
    end
  end
end
