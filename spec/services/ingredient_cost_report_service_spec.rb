require "rails_helper"

# #209 — le coût des matières valorisé aux prix historisés.
#
# LE critère central : « changer un prix ne modifie aucun chiffre déjà produit
# pour une période passée ». Chaque quantité est valorisée au prix en vigueur à
# la date de SA fournée, pas au prix du jour où l'on regarde.
RSpec.describe IngredientCostReportService do
  let(:june) { Date.new(2026, 6, 5) }
  let(:august) { Date.new(2026, 8, 7) }

  let!(:default_pickup) { create(:pickup_location, :default) }

  let(:figues) { create(:ingredient, name: "Figues") }
  let(:froment) { create(:flour, name: "Froment T65", price_per_kg_cents: nil) }

  let(:product) { create(:product, :bread, name: "Pain aux figues") }
  let!(:product_flour) { create(:product_flour, product: product, flour: froment, percentage: 100) }
  let!(:variant) { create(:product_variant, product: product, name: "Grand", flour_quantity: 1_000, price_cents: 650) }
  let!(:variant_ingredient) { VariantIngredient.create!(product_variant: variant, ingredient: figues, quantity: 50) }

  def sell(date:, qty:)
    bake_day = BakeDay.find_by(baked_on: date) || create(:bake_day, baked_on: date, cut_off_at: date - 2.days)
    order = create(:order, :paid, customer: create(:customer), bake_day: bake_day, total_cents: qty * 650)
    create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: 650)
  end

  def report(from, to)
    described_class.call(start_date: from, end_date: to)
  end

  describe "la valorisation" do
    before do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.new(2026, 6, 1))
      create(:flour_price, flour: froment, amount_cents: 80, active_from: Date.new(2026, 6, 1))
    end

    it "valorise les ingrédients au prix de leur fournée" do
      sell(date: june, qty: 10) # 10 × 50 g = 500 g de figues

      line = report(june, june).ingredient_lines.first

      expect(line.subject).to eq(figues)
      expect(line.grams).to eq(500)
      # 0,5 kg × 10 € = 5,00 €
      expect(line.cost_cents).to eq(500)
    end

    it "valorise aussi les farines" do
      sell(date: june, qty: 10) # 10 × 1 000 g de pâte, 100 % froment

      line = report(june, june).flour_lines.first

      expect(line.subject).to eq(froment)
      expect(line.grams).to eq(10_000)
      # 10 kg × 0,80 € = 8,00 €
      expect(line.cost_cents).to eq(800)
    end

    it "totalise ingrédients et farines" do
      sell(date: june, qty: 10)

      expect(report(june, june).total_cost_cents).to eq(500 + 800)
    end
  end

  # ---- Le cœur de l'issue ----
  describe "un reporting passé ne change jamais" do
    before do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.new(2026, 6, 1))
      create(:flour_price, flour: froment, amount_cents: 80, active_from: Date.new(2026, 6, 1))
      sell(date: june, qty: 10)
    end

    it "reste identique après l'ajout d'un prix postérieur" do
      before_change = report(june, june)

      # On rachète des figues, plus cher, en août.
      create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))
      create(:flour_price, flour: froment, amount_cents: 95, active_from: Date.new(2026, 8, 1))

      after_change = report(june, june)

      expect(after_change.total_cost_cents).to eq(before_change.total_cost_cents)
      expect(after_change.ingredient_lines.first.cost_cents).to eq(500)
      expect(after_change.flour_lines.first.cost_cents).to eq(800)
    end

    it "applique le nouveau prix à la période suivante, et elle seule" do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))
      sell(date: august, qty: 10)

      june_report = report(june, june)
      august_report = report(august, august)

      expect(june_report.ingredient_lines.first.cost_cents).to eq(500)   # 0,5 kg × 10 €
      expect(august_report.ingredient_lines.first.cost_cents).to eq(700) # 0,5 kg × 14 €
    end

    it "valorise chaque fournée à SON prix même dans une période qui les couvre toutes" do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))
      sell(date: august, qty: 10)

      line = report(june, august).ingredient_lines.first

      expect(line.grams).to eq(1_000)
      # 500 g à 10 € + 500 g à 14 € = 5,00 + 7,00
      expect(line.cost_cents).to eq(1_200)
    end
  end

  describe "un élément sans prix" do
    it "n'est pas compté pour zéro : sa quantité est visible, son coût est nil" do
      sell(date: june, qty: 10)

      result = report(june, june)
      line = result.ingredient_lines.first

      expect(line.grams).to eq(500)
      expect(line.cost_cents).to be_nil
      expect(line.priced?).to be false
      expect(line.partially_priced?).to be true
      expect(result.unpriced_count).to eq(2) # figues + froment
    end

    it "signale la part non valorisée quand seule une partie de la période a un prix" do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))
      sell(date: june, qty: 10)
      sell(date: august, qty: 10)

      line = report(june, august).ingredient_lines.first

      expect(line.cost_cents).to eq(700)          # seul août est valorisé
      expect(line.missing_price_grams).to eq(500) # juin ne l'est pas
      expect(line.partially_priced?).to be true
    end

    it "ne casse pas les calculs de coût de revient existants" do
      create(:variant_cost_price, product_variant: variant, amount_cents: 200, active_from: Date.new(2026, 1, 1))

      expect(variant.cost_price_cents(on: june)).to eq(200)
    end
  end

  describe "le périmètre" do
    before { create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.new(2026, 6, 1)) }

    it "ignore les commandes hors période" do
      sell(date: june, qty: 10)

      expect(report(august, august).ingredient_lines).to be_empty
    end

    it "ignore les commandes non finalisées" do
      bake_day = create(:bake_day, baked_on: june, cut_off_at: june - 2.days)
      order = create(:order, :unpaid, customer: create(:customer), bake_day: bake_day, total_cents: 650)
      create(:order_item, order: order, product_variant: variant, qty: 1, unit_price_cents: 650)

      expect(report(june, june).ingredient_lines).to be_empty
    end
  end
end
