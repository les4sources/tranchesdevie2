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
end
