require "rails_helper"

# Les pâtons d'une Pizza party privée pèsent sur le pétrin de la fournée qui les
# prépare, mais pas sur son four ni sur ses moules (#170) : les pizzas cuisent
# dans le four à bois, pas dans le four à pain de la fournée.
RSpec.describe BakeCapacityService, "pâtons de Pizza party" do
  let(:tuesday) { Date.new(2026, 9, 1) }
  let(:friday)  { Date.new(2026, 9, 4) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:tuesday_bake) { create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days) }
  let!(:friday_bake)  { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let!(:production_setting) do
    ProductionSetting.create!(oven_capacity_grams: 100_000, market_day_oven_capacity_grams: 200_000)
  end
  let!(:flour) { Flour.create!(name: "Froment T65", kneader_limit_grams: 50_000, position: 1) }
  let!(:mold_type) { MoldType.create!(name: "Moule à cake", limit: 40, position: 1) }

  let(:customer) { create(:customer) }

  # Pain ordinaire : pétrin + four + moules.
  let(:bread_product) { create(:product, :bread, category: :breads) }
  let!(:bread_flour) { create(:product_flour, product: bread_product, flour: flour, percentage: 100) }
  let(:bread_variant) do
    create(:product_variant, product: bread_product, price_cents: 450,
                             flour_quantity: 500, mold_type: mold_type)
  end

  # Pâton de party : même farine, mais catégorie dough_balls et aucun moule.
  let(:party_product) { create(:product, :pizza_party, category: :dough_balls) }
  let!(:party_flour) { create(:product_flour, product: party_product, flour: flour, percentage: 100) }
  let(:paton) do
    create(:product_variant, product: party_product, name: "une boule",
                             price_cents: 500, flour_quantity: 200, mold_type: nil)
  end

  def book_party(held_on:, slot:, qty: 10, status: :paid)
    event = create(:party_event, :private_party, held_on: held_on, slot: slot)
    order = PartyOrderCreationService.new(
      customer: customer, party_event: event,
      cart_items: [ { "product_variant_id" => paton.id.to_s, "qty" => qty.to_s } ]
    ).call
    order.update!(status: status)
    order
  end

  def usage_for(bake_day)
    described_class.new(bake_day).usage
  end

  def kneader_grams(bake_day)
    usage_for(bake_day)[:kneader].find { |e| e[:flour] == flour }[:used]
  end

  def molds_used(bake_day)
    usage_for(bake_day)[:molds].find { |e| e[:mold_type] == mold_type }[:used]
  end

  describe "sans aucune party — non-régression" do
    it "donne exactement les chiffres du pain seul" do
      create(:order, :paid, customer: customer, bake_day: friday_bake).tap do |order|
        create(:order_item, order: order, product_variant: bread_variant, qty: 4)
      end

      expect(kneader_grams(friday_bake)).to eq(2_000)   # 4 × 500 g
      expect(usage_for(friday_bake)[:oven][:used]).to eq(2_000)
      expect(molds_used(friday_bake)).to eq(4)
    end

    it "donne zéro partout sur une fournée vide" do
      expect(kneader_grams(friday_bake)).to eq(0)
      expect(usage_for(friday_bake)[:oven][:used]).to eq(0)
      expect(molds_used(friday_bake)).to eq(0)
    end
  end

  describe "avec une party à préparer" do
    before { book_party(held_on: friday, slot: :soir, qty: 10) }

    it "compte les pâtons dans le PÉTRIN" do
      expect(kneader_grams(friday_bake)).to eq(2_000) # 10 × 200 g
    end

    it "ne les compte PAS dans le four" do
      expect(usage_for(friday_bake)[:oven][:used]).to eq(0)
    end

    it "ne les compte PAS dans les moules" do
      expect(molds_used(friday_bake)).to eq(0)
    end

    it "s'ajoute au pain sans le remplacer, au pétrin seulement" do
      create(:order, :paid, customer: customer, bake_day: friday_bake).tap do |order|
        create(:order_item, order: order, product_variant: bread_variant, qty: 4)
      end

      expect(kneader_grams(friday_bake)).to eq(4_000)  # 2 000 pain + 2 000 pâtons
      expect(usage_for(friday_bake)[:oven][:used]).to eq(2_000) # le pain seul
      expect(molds_used(friday_bake)).to eq(4)
    end
  end

  describe "affectation" do
    it "charge le pétrin de la fournée précédente pour une party de MIDI" do
      book_party(held_on: friday, slot: :midi, qty: 10)

      expect(kneader_grams(tuesday_bake)).to eq(2_000)
      expect(kneader_grams(friday_bake)).to eq(0)
    end

    it "charge la fournée du vendredi pour une party du samedi" do
      book_party(held_on: Date.new(2026, 9, 5), slot: :soir, qty: 10)

      expect(kneader_grams(friday_bake)).to eq(2_000)
      expect(kneader_grams(tuesday_bake)).to eq(0)
    end

    it "ignore une party annulée" do
      book_party(held_on: friday, slot: :soir, qty: 10, status: :cancelled)

      expect(kneader_grams(friday_bake)).to eq(0)
    end
  end
end
