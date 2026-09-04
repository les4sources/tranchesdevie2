require "rails_helper"

# Le point de retrait sur les drapeaux (#253) : les boulangers trient les cartes
# en pile au moment de l'emballage, sans quitter l'onglet.
RSpec.describe Admin::BakeDayDashboard, "#customer_breakdown — points de retrait" do
  let(:bake_day) { create(:bake_day) }
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée", position: 1) }
  let!(:champalle) { create(:pickup_location, name: "Ferme de Champalle", position: 3) }
  let(:customer) { create(:customer, last_name: "Zorro", first_name: "Alba") }
  let(:variant) { create(:product_variant) }

  before do
    bake_day.pickup_location_ids = [ default_location.id, anhee.id, champalle.id ]
    bake_day.save!
  end

  def place_order(location)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, pickup_location: location)
    create(:order_item, order: order, product_variant: variant, qty: 1)
    order
  end

  def entry_for(customer)
    described_class.new(bake_day).customer_breakdown.find { |e| e[:customer] == customer }
  end

  it "expose le lieu de retrait du client" do
    place_order(anhee)

    expect(entry_for(customer)[:pickup_locations]).to eq([ anhee ])
  end

  it "liste les DEUX lieux quand le client a deux commandes à deux endroits" do
    place_order(anhee)
    place_order(default_location)

    expect(entry_for(customer)[:pickup_locations]).to contain_exactly(anhee, default_location)
  end

  it "trie les lieux par position, comme l'onglet « Par point de retrait »" do
    place_order(champalle)
    place_order(anhee)
    place_order(default_location)

    expect(entry_for(customer)[:pickup_locations]).to eq([ default_location, anhee, champalle ])
  end

  it "ne répète pas un lieu partagé par deux commandes" do
    place_order(anhee)
    place_order(anhee)

    expect(entry_for(customer)[:pickup_locations]).to eq([ anhee ])
  end

  # `orders.pickup_location_id` est NOT NULL en base et l'association est requise :
  # une commande sans lieu ne peut PAS exister — la base refuse même un
  # `update_columns`. Le `compact` du presenter est donc une garde défensive ; on
  # la teste en simulant l'association nulle, faute de pouvoir la produire.
  it "ignore un lieu nul plutôt que de le porter sur la carte" do
    place_order(anhee)
    allow_any_instance_of(Order).to receive(:pickup_location).and_return(nil)

    expect(entry_for(customer)[:pickup_locations]).to be_empty
  end

  it "porte un lieu soft-deleted sans planter" do
    place_order(anhee)
    anhee.soft_delete!

    expect(entry_for(customer)[:pickup_locations].map(&:name)).to eq([ "Marché d'Anhée" ])
  end
end
