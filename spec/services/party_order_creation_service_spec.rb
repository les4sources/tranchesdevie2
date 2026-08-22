require "rails_helper"

RSpec.describe PartyOrderCreationService do
  let(:customer) { create(:customer) }
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let(:event) { create(:party_event, :public_party) }
  let(:product) { create(:product, :pizza_party_public) }
  let(:adulte) { create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300) }
  let(:cart_items) { [ { "product_variant_id" => adulte.id.to_s, "qty" => "3" } ] }

  it "crée une commande party sans fournée, liée à l'événement" do
    order = described_class.new(customer: customer, party_event: event, cart_items: cart_items).call

    expect(order).to be_a(Order)
    expect(order.bake_day).to be_nil
    expect(order.party_event).to eq(event)
    expect(order.party?).to be true
    expect(order.pickup_location).to eq(default_pickup)
    expect(order.order_items.sum(&:qty)).to eq(3)
    expect(order.total_cents).to eq(3_000)
  end

  it "applique la remise groupe au total" do
    group = create(:group, discount_percent: 10)
    create(:customer_group, customer: customer, group: group)

    order = described_class.new(customer: customer, party_event: event, cart_items: cart_items).call

    expect(order.total_cents).to eq(2_700) # 3000 − 10 %
  end

  it "refuse sans événement" do
    service = described_class.new(customer: customer, party_event: nil, cart_items: cart_items)

    expect(service.call).to be false
    expect(service.errors).to be_present
  end

  it "refuse un panier vide" do
    service = described_class.new(customer: customer, party_event: event, cart_items: [])

    expect(service.call).to be false
  end
end
