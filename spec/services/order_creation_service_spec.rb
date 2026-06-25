require "rails_helper"

# #99 : le nom du groupe « 4 Sources » est persisté sur la commande.
RSpec.describe OrderCreationService do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:variant) { create(:product_variant) } # active, canal "store"
  let(:cart_items) { [ { "product_variant_id" => variant.id, "qty" => 1 } ] }

  def build_service(group_name: nil)
    described_class.new(
      customer: customer,
      bake_day: bake_day,
      cart_items: cart_items,
      payment_method: "cash",
      skip_capacity_check: true,
      group_name: group_name
    )
  end

  it "persists the group name on the order when provided" do
    order = build_service(group_name: "Groupe de Joséphine").call

    expect(order).to be_a(Order)
    expect(order.group_name).to eq("Groupe de Joséphine")
  end

  it "stores nil when the group name is blank" do
    order = build_service(group_name: "   ").call

    expect(order.group_name).to be_nil
  end

  it "stores nil when no group name is provided" do
    order = build_service.call

    expect(order.group_name).to be_nil
  end
end
