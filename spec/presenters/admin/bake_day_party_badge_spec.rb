require "rails_helper"

# #202 — le presenter derrière la signalétique party : ce que le boulanger doit
# lire d'un coup d'œil (client, pâtons, créneau, privé/public) et la fusion du
# flux des commandes, sans laquelle les party — qui n'ont pas de `bake_day` —
# resteraient absentes de la liste.
RSpec.describe Admin::BakeDayDashboard, "signalétique des parties" do
  let(:friday) { Date.new(2026, 9, 4) }
  let(:saturday) { Date.new(2026, 9, 5) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:friday_bake) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:customer) { create(:customer, first_name: "Fabienne", last_name: "Renard") }

  let(:private_product) { create(:product, :pizza_party, category: :dough_balls) }
  let(:paton) { create(:product_variant, product: private_product, name: "une boule", price_cents: 500, flour_quantity: 200) }
  let(:public_product) { create(:product, :pizza_party_public, category: :dough_balls) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, flour_quantity: 200) }

  subject(:dashboard) { described_class.new(friday_bake) }

  def book(event:, variant:, qty:)
    order = PartyOrderCreationService.new(
      customer: customer, party_event: event,
      cart_items: [ { "product_variant_id" => variant.id.to_s, "qty" => qty.to_s } ]
    ).call
    order.update!(status: :paid)
    order
  end

  describe "#parties_to_prepare" do
    it "expose le client, les pâtons et le créneau d'une party privée" do
      event = create(:party_event, :private_party, held_on: friday, slot: :soir)
      book(event: event, variant: paton, qty: 11)

      entry = dashboard.parties_to_prepare.first

      expect(entry[:customer_name]).to eq("Fabienne Renard")
      expect(entry[:paton_count]).to eq(11)
      expect(entry[:slot_label]).to eq("Soir")
      expect(entry[:private]).to be true
      expect(entry[:kind_label]).to eq("Party privée")
      expect(entry[:same_day]).to be true
    end

    it "distingue une party publique" do
      event = create(:party_event, :public_party, held_on: friday)
      book(event: event, variant: adulte, qty: 5)

      entry = dashboard.parties_to_prepare.first

      expect(entry[:private]).to be false
      expect(entry[:kind_label]).to eq("Party publique")
    end

    it "signale une party préparée pour un autre jour" do
      event = create(:party_event, :private_party, held_on: saturday, slot: :soir)
      book(event: event, variant: paton, qty: 7)

      entry = dashboard.parties_to_prepare.first

      expect(entry[:same_day]).to be false
      expect(entry[:held_on]).to eq(saturday)
    end
  end

  describe "#timeline_entries" do
    let!(:bread) { create(:product, :bread, name: "Pain froment") }
    let!(:variant) { create(:product_variant, product: bread, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650) }

    it "fusionne les commandes de pain et les commandes party, dans l'ordre d'arrivée" do
      bread_order = create(:order, :paid, customer: customer, bake_day: friday_bake, total_cents: 1_300)
      create(:order_item, order: bread_order, product_variant: variant, qty: 2, unit_price_cents: 650)

      event = create(:party_event, :private_party, held_on: friday, slot: :soir)
      party_order = book(event: event, variant: paton, qty: 11)

      entries = dashboard.timeline_entries

      expect(entries.map { |e| e[:order].id }).to contain_exactly(bread_order.id, party_order.id)
      expect(entries.map { |e| e[:order].created_at }).to eq(entries.map { |e| e[:order].created_at }.sort)

      party_entry = entries.find { |e| e[:order].id == party_order.id }
      bread_entry = entries.find { |e| e[:order].id == bread_order.id }

      expect(party_entry[:party][:paton_count]).to eq(11)
      expect(bread_entry[:party]).to be_nil
    end

    it "reste exactement la liste des commandes quand il n'y a aucune party" do
      bread_order = create(:order, :paid, customer: customer, bake_day: friday_bake, total_cents: 1_300)
      create(:order_item, order: bread_order, product_variant: variant, qty: 2, unit_price_cents: 650)

      expect(dashboard.timeline_entries.map { |e| e[:order].id }).to eq([ bread_order.id ])
      expect(dashboard.timeline_entries.map { |e| e[:party] }).to eq([ nil ])
    end
  end
end
