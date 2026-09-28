require "rails_helper"

# Le bouton « Proposer une répartition » du calculateur de fournées : pesée des
# produits du jour, pâtons avec le froment, et remplacement des fournées.
RSpec.describe BatchProposalService do
  let(:bake_day) { create(:bake_day) }

  let(:petit_epeautre) { create(:flour, name: "Petit épeautre") }
  let(:epeautre)       { create(:flour, name: "Épeautre") }
  let(:froment)        { create(:flour, name: "Froment") }
  let(:froment_patons) { create(:flour, name: "Froment (pâtons)") }

  let(:customer) { create(:customer) }
  let(:order) { create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1_000) }

  # Un produit d'une seule farine, et `units` pains de `grams` sur la commande.
  def line(name, flour:, units:, grams: 1_000, category: :breads)
    product = create(:product, name: name, category: category)
    create(:product_flour, product: product, flour: flour, percentage: 100)
    variant = create(:product_variant, product: product, flour_quantity: grams)
    create(:order_item, order: order, product_variant: variant, qty: units)
  end

  describe ".flour_rank" do
    it "suit l'ordre de Claire, blé ancien entre seigle et froment" do
      ranks = [ "Petit épeautre", "Épeautre", "Seigle", "Blé ancien", "Froment", "Froment (pâtons)" ]
                .map { |name| described_class.flour_rank(Flour.new(name: name)) }

      expect(ranks).to eq([ 0, 1, 2, 3, 4, 4 ])
    end
  end

  describe ".main_flour" do
    it "classe un produit à plusieurs farines selon la plus présente" do
      product = create(:product)
      create(:product_flour, product: product, flour: froment, percentage: 60)
      create(:product_flour, product: product, flour: epeautre, percentage: 40)

      expect(described_class.main_flour(product.reload)).to eq(froment)
    end
  end

  describe "#apply!" do
    let!(:petit) { line("Pain au petit épeautre", flour: petit_epeautre, units: 10) }
    let!(:epeautre_line) { line("Pain d'épeautre", flour: epeautre, units: 25) }
    let!(:froment_line) { line("Pain au froment", flour: froment, units: 60) }
    let!(:patons) { line("Pâtons", flour: froment_patons, units: 30, grams: 250, category: :dough_balls) }

    it "sépare épeautres et froment dès 70 kg de pain, dans l'ordre de passage" do
      expect(described_class.new(bake_day).apply!).to eq(2)

      first, second = bake_day.batches.ordered.to_a
      expect([ first.name, second.name ]).to eq([ "Fournée 1", "Fournée 2" ])
      expect(first.order_items).to contain_exactly(petit, epeautre_line)
      expect(second.order_items).to include(froment_line)
    end

    it "met les pâtons dans la fournée froment, hors des 70 kg" do
      described_class.new(bake_day).apply!

      froment_batch = froment_line.reload.batch
      expect(patons.reload.batch).to eq(froment_batch)
      expect(Admin::BatchPlanner.new(bake_day).batch_stats.last[:paton_dough_grams]).to eq(7_500)
    end

    it "remplace les fournées existantes sans perdre de ligne" do
      old = create(:batch, bake_day: bake_day, name: "À la main", position: 1)
      froment_line.update!(batch: old)

      described_class.new(bake_day).apply!

      expect(Batch.exists?(old.id)).to be(false)
      expect(Admin::BatchPlanner.new(bake_day)).to be_fully_assigned
    end
  end

  it "ne touche à rien sans ligne à répartir" do
    existing = create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1)

    expect(described_class.new(bake_day).apply!).to eq(0)
    expect(Batch.exists?(existing.id)).to be(true)
  end

  it "fait une seule fournée jusqu'à 70 kg" do
    line("Pain d'épeautre", flour: epeautre, units: 30)
    line("Pain au froment", flour: froment, units: 40)

    expect(described_class.new(bake_day).apply!).to eq(1)
  end
end
