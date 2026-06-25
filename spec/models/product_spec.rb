require "rails_helper"

RSpec.describe Product, type: :model do
  describe "internal_category" do
    it "défaut à boulangerie" do
      product = Product.new(name: "Pain", category: :breads, position: 1)
      expect(product.internal_category).to eq("boulangerie")
    end

    it "expose les catégories internes attendues" do
      expect(Product.internal_categories.keys).to eq(%w[boulangerie epicerie traiteur autre])
    end

    it "permet de choisir une catégorie de revente" do
      product = create(:product, :epicerie)
      expect(product.reload.internal_category).to eq("epicerie")
      expect(product.internal_category_epicerie?).to be(true)
    end
  end

  describe "#incurs_bag_cost? (#52)" do
    it "is true for an in-house produced bread" do
      product = build(:product, category: :breads, internal_category: :boulangerie)
      expect(product.incurs_bag_cost?).to be(true)
    end

    it "is false for dough balls (pâtons)" do
      product = build(:product, :dough_ball, internal_category: :boulangerie)
      expect(product.incurs_bag_cost?).to be(false)
    end

    it "is false for a resold (non-produced) bread" do
      product = build(:product, category: :breads, internal_category: :epicerie)
      expect(product.incurs_bag_cost?).to be(false)
    end
  end
end
