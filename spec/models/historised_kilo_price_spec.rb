require "rails_helper"

# #209 — prix au kilo historisés par date d'effet.
#
# « On met un historique, on dit c'était le prix à partir de telle date […] le
# reporting ne devrait jamais changer. »
RSpec.describe HistorisedKiloPrice do
  let(:figues) { create(:ingredient, name: "Figues") }
  let(:froment) { create(:flour, name: "Froment T65", price_per_kg_cents: nil) }

  describe "la résolution à une date" do
    before do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.new(2026, 6, 1))
      create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))
    end

    it "renvoie le prix de juin au 15 juillet" do
      expect(figues.price_per_kg_cents_on(Date.new(2026, 7, 15))).to eq(1_000)
    end

    it "renvoie le prix d'août au 15 août" do
      expect(figues.price_per_kg_cents_on(Date.new(2026, 8, 15))).to eq(1_400)
    end

    it "prend le nouveau prix dès sa date d'effet — borne incluse" do
      expect(figues.price_per_kg_cents_on(Date.new(2026, 8, 1))).to eq(1_400)
      expect(figues.price_per_kg_cents_on(Date.new(2026, 7, 31))).to eq(1_000)
    end

    it "renvoie nil avant tout palier — un prix inconnu n'est pas un prix nul" do
      expect(figues.price_per_kg_cents_on(Date.new(2026, 5, 31))).to be_nil
      expect(figues.price_per_kg_euros_on(Date.new(2026, 5, 31))).to be_nil
    end

    it "expose le prix en euros" do
      expect(figues.price_per_kg_euros_on(Date.new(2026, 8, 15))).to eq(14.0)
    end
  end

  describe "un élément sans aucun prix" do
    it "ne casse rien et se signale" do
      expect(figues.priced?).to be false
      expect(figues.price_per_kg_cents_on).to be_nil
      expect { figues.price_per_kg_cents_on }.not_to raise_error
    end
  end

  describe "les farines suivent le même mécanisme" do
    it "résout le prix à la date" do
      create(:flour_price, flour: froment, amount_cents: 80, active_from: Date.new(2026, 1, 1))
      create(:flour_price, flour: froment, amount_cents: 95, active_from: Date.new(2026, 7, 1))

      expect(froment.price_per_kg_cents_on(Date.new(2026, 6, 30))).to eq(80)
      expect(froment.price_per_kg_cents_on(Date.new(2026, 7, 1))).to eq(95)
    end

    it "affiche le prix courant depuis l'historique" do
      create(:flour_price, flour: froment, amount_cents: 95, active_from: Date.current - 1)

      expect(froment.price_per_kg_euros).to eq(0.95)
    end

    it "retombe sur l'ancienne colonne tant qu'aucun palier n'existe" do
      legacy = create(:flour, name: "Seigle", price_per_kg_cents: 120)

      expect(legacy.price_per_kg_euros).to eq(1.2)
    end
  end

  describe "la correction d'un palier" do
    it "reste possible — une faute de frappe doit pouvoir se réparer" do
      price = create(:ingredient_price, ingredient: figues, amount_cents: 10_000, active_from: Date.new(2026, 6, 1))

      price.update!(amount_cents: 1_000)

      expect(figues.price_per_kg_cents_on(Date.new(2026, 7, 1))).to eq(1_000)
    end

    it "et la suppression fait retomber sur le palier précédent" do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.new(2026, 6, 1))
      newer = create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))

      newer.destroy!

      expect(figues.price_per_kg_cents_on(Date.new(2026, 8, 15))).to eq(1_000)
    end
  end
end
