require "rails_helper"

# Circulation du point de retrait (#148) à travers les services de création de
# commande : checkout (OrderCreationService) et calendrier (PlannedOrderService).
RSpec.describe "Point de retrait dans les services de commande", type: :service do
  let!(:default_location) { create(:pickup_location, :default) }
  let(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }

  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:variant) { create(:product_variant, price_cents: 700) }
  let(:cart_items) { [ { "product_variant_id" => variant.id, "qty" => 2 } ] }

  describe OrderCreationService do
    def build_service(pickup_location:)
      described_class.new(
        customer: customer,
        bake_day: bake_day,
        cart_items: cart_items,
        payment_method: "cash",
        pickup_location: pickup_location
      )
    end

    it "persiste le point de retrait choisi" do
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!

      order = build_service(pickup_location: anhee).call

      expect(order).to be_a(Order)
      expect(order.pickup_location).to eq(anhee)
    end

    it "retombe sur le lieu par défaut quand aucun lieu n'est fourni" do
      order = build_service(pickup_location: nil).call

      expect(order.pickup_location).to eq(default_location)
    end

    it "rejette un lieu non ouvert sur la fournée" do
      # `anhee` n'est PAS coché sur cette fournée.
      service = build_service(pickup_location: anhee)

      expect(service.call).to be false
      expect(service.errors.join).to include("n'est pas disponible pour cette fournée")
      expect(Order.count).to eq(0)
    end
  end

  describe PlannedOrderService do
    let(:items) { [ { product_variant_id: variant.id, qty: 2 } ] }

    before do
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!
    end

    it "persiste le point de retrait à l'upsert" do
      result = described_class.upsert(
        customer: customer, bake_day: bake_day, items: items, pickup_location: anhee
      )

      expect(result[:order].pickup_location).to eq(anhee)
    end

    it "CONSERVE le lieu quand seuls les articles changent" do
      described_class.upsert(customer: customer, bake_day: bake_day, items: items, pickup_location: anhee)

      # 2e passage sans lieu (le client ne modifie que ses articles).
      result = described_class.upsert(
        customer: customer,
        bake_day: bake_day,
        items: [ { product_variant_id: variant.id, qty: 5 } ]
      )

      expect(result[:order].pickup_location).to eq(anhee)
      expect(result[:order].order_items.sum(&:qty)).to eq(5)
    end

    it "permet de changer de lieu date par date" do
      described_class.upsert(customer: customer, bake_day: bake_day, items: items, pickup_location: anhee)

      result = described_class.upsert(
        customer: customer, bake_day: bake_day, items: items, pickup_location: default_location
      )

      expect(result[:order].pickup_location).to eq(default_location)
    end

    it "rejette un lieu non ouvert sur la fournée" do
      closed = create(:pickup_location, name: "Marché de Dinant")

      result = described_class.upsert(
        customer: customer, bake_day: bake_day, items: items, pickup_location: closed
      )

      expect(result[:error]).to include("n'est pas disponible pour cette fournée")
    end
  end

  describe "dernier lieu choisi par le client" do
    before do
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!
    end

    it "renvoie le lieu de la dernière commande non annulée" do
      create(:order, customer: customer, bake_day: bake_day, pickup_location: default_location)
      create(:order, customer: customer, bake_day: bake_day, pickup_location: anhee)

      expect(customer.last_pickup_location).to eq(anhee)
    end

    it "ignore les commandes annulées" do
      create(:order, customer: customer, bake_day: bake_day, pickup_location: default_location)
      create(:order, :cancelled, customer: customer, bake_day: bake_day, pickup_location: anhee)

      expect(customer.last_pickup_location).to eq(default_location)
    end

    it "renvoie nil pour un client sans commande" do
      expect(create(:customer).last_pickup_location).to be_nil
    end
  end
end
