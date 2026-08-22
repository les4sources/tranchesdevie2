require "rails_helper"

RSpec.describe OrderItem, type: :model do
  describe "#full_name (#98)" do
    it "combines the product name and the variant name" do
      product = create(:product, name: "Pain froment")
      variant = create(:product_variant, product: product, name: "Petit 600 g")
      item = build(:order_item, product_variant: variant)

      expect(item.full_name).to eq("Pain froment — Petit 600 g")
    end
  end
end
