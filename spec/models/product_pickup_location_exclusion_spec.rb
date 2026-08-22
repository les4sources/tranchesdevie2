require "rails_helper"

# Exclusion produit ↔ lieu de retrait (#152).
RSpec.describe ProductPickupLocationExclusion do
  let(:product) { create(:product) }
  let(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }

  it "refuse un doublon produit/lieu" do
    described_class.create!(product: product, pickup_location: anhee)
    dup = described_class.new(product: product, pickup_location: anhee)

    expect(dup).not_to be_valid
  end

  describe "Product#orderable_at?" do
    let(:default_location) { create(:pickup_location, :default) }

    it "est commandable partout sans exclusion" do
      expect(product.orderable_at?(anhee)).to be(true)
      expect(product.orderable_at?(default_location)).to be(true)
    end

    it "n'est pas commandable au lieu exclu, mais l'est ailleurs" do
      product.excluded_pickup_locations << anhee

      expect(product.orderable_at?(anhee)).to be(false)
      expect(product.orderable_at?(default_location)).to be(true)
    end

    it "est commandable quand aucun lieu n'est fourni" do
      product.excluded_pickup_locations << anhee
      expect(product.orderable_at?(nil)).to be(true)
    end
  end
end
