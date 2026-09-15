require 'rails_helper'

# Une réservation validée mais NON PAYÉE ne pèse sur rien (#pizza-parties).
#
# C'est la conséquence structurelle du statut `awaiting_payment` : un test par
# consommateur, parce que l'exclusion doit tenir partout, pas seulement là où on
# a pensé à la vérifier.
RSpec.describe "Une party validée non payée" do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let(:flour) { create(:flour, kneader_limit_grams: 50_000) }
  let!(:party_product) do
    product = create(:product, :pizza_party)
    create(:product_flour, product: product, flour: flour, percentage: 100)
    product
  end
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200, flour_quantity: 250) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  let(:customer) { create(:customer, phone_e164: "+32470121212", email: "isolation@example.com") }
  let(:party_request) { create(:party_request, customer: customer) }
  let!(:order) { PartyDecisionService.new(party_request, decided_by: "Romane").accept }
  let!(:bake_day) { create(:bake_day, baked_on: party_request.held_on) }

  before { PartyPaymentService.new(order).confirm_headcount!(20) }

  it "est absente du chiffre d'affaires (Order.completed)" do
    expect(Order.completed).not_to include(order)
    expect(Order::COMPLETED_STATUSES).not_to include("awaiting_payment")
  end

  it "est absente des commandes party comptabilisées" do
    expect(BakeDayPartyOrders.completed(bake_day)).not_to include(order)
  end

  it "est absente des commandes party de production" do
    expect(BakeDayPartyOrders.production(bake_day)).not_to include(order)
  end

  it "ne consomme aucune farine ni pétrin" do
    usage = BakeCapacityService.new(bake_day).usage
    expect(usage[:kneader].sum { |entry| entry[:used] }).to eq(0)
  end

  it "est absente de l'index des parties privées" do
    entries = Admin::PrivatePartyIndex.new.entries
    expect(entries.map { |entry| entry.order.id }).not_to include(order.id)
  end

  it "apparaît en revanche dans la prévision « à confirmer » du tableau de bord" do
    dashboard = Admin::BakeDayDashboard.new(bake_day)

    expect(dashboard.parties_to_confirm.map { |e| e[:order].id }).to include(order.id)
    expect(dashboard.parties_to_prepare.map { |e| e[:order].id }).not_to include(order.id)
    expect(dashboard.parties_to_confirm.first[:paton_count]).to eq(20)
  end

  it "rejoint la production dès qu'elle est payée" do
    order.update!(status: :paid, payment_status: :paid)

    expect(BakeDayPartyOrders.production(bake_day)).to include(order)
    expect(BakeCapacityService.new(bake_day).usage[:kneader].sum { |e| e[:used] }).to eq(20 * 250)
  end
end
