require "rails_helper"

# Garde serveur (#152) : un produit exclu pour le lieu de retrait choisi ne peut
# pas être commandé à ce lieu. Couvre les trois chemins (le service est partagé).
RSpec.describe OrderCreationService do
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }
  let(:bake_day) { create(:bake_day, :tuesday, cut_off_at: 2.days.from_now) }
  let(:product) { create(:product, name: "Pain surprise", channel: "store") }
  let(:variant) { create(:product_variant, product: product, channel: "store", price_cents: 700) }
  let(:customer) { create(:customer) }

  before do
    bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
    bake_day.save!
  end

  def cart_for(variant, qty = 1)
    [ { "product_variant_id" => variant.id.to_s, "qty" => qty } ]
  end

  def build(pickup_location:)
    described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant),
      pickup_location: pickup_location, skip_capacity_check: true
    )
  end

  context "quand le produit est exclu pour le lieu choisi" do
    before { product.excluded_pickup_locations << anhee }

    it "refuse la commande avec un message nommant produit, lieu et action" do
      service = build(pickup_location: anhee)

      expect(service.call).to be(false)
      message = service.errors.join(" ")
      expect(message).to include("Pain surprise")
      expect(message).to include(CGI.unescape_html("Marché d'Anhée"))
      expect(message).to match(/[Rr]etirez/)
    end

    it "autorise la commande pour un lieu non exclu" do
      service = build(pickup_location: default_location)

      expect(service.call).to be_a(Order)
    end
  end

  context "quand le produit n'a aucune exclusion" do
    it "ne bloque rien (aucune régression)" do
      expect(build(pickup_location: anhee).call).to be_a(Order)
    end
  end
end
