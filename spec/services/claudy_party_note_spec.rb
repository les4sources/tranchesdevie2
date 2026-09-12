require 'rails_helper'

# Composition du post-it « Pizza party » posé sur le calendrier de claudy (#259).
# Logique pure : aucun appel HTTP ici, seulement les règles de libellé.
RSpec.describe ClaudyPartyNote do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let(:customer) { create(:customer, first_name: 'Michael', last_name: 'Hulet') }
  let(:party_event) { create(:party_event, :private_party, held_on: Date.current.next_occurring(:friday)) }

  let(:party_product) { create(:product, :pizza_party, channel: 'store') }
  let(:party_variant) { create(:product_variant, product: party_product, price_cents: 500, channel: 'store') }
  let(:forfait_product) { create(:product, :pizza_party_forfait) }
  let(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4_000, channel: 'store') }

  # Une commande party réaliste : N boules (= N personnes) + la ligne forfait,
  # unique quel que soit le nombre de convives.
  def build_party_order(patons:, group_name: nil, customer: self.customer, event: party_event)
    order = create(:order, customer: customer, bake_day: nil, party_event: event,
                           source: :party, group_name: group_name)
    create(:order_item, order: order, product_variant: party_variant, qty: patons, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait_variant, qty: 1, unit_price_cents: 4_000)
    order.reload
  end

  describe '#body' do
    it "rend exactement les deux lignes attendues pour un groupe de 18 en soirée" do
      order = build_party_order(patons: 18)

      expect(described_class.new(order).body).to eq("Pizza Party privée\nSoirée : Michael Hulet - 18 personnes")
    end

    it "accorde au singulier pour une seule personne" do
      order = build_party_order(patons: 1)

      expect(described_class.new(order).body).to end_with('- 1 personne')
    end

    it "préfère le nom du groupe au nom du client quand il est présent" do
      order = build_party_order(patons: 12, group_name: 'Les Sourciers')

      expect(described_class.new(order).body).to eq("Pizza Party privée\nSoirée : Les Sourciers - 12 personnes")
    end

    it "écrit « Midi » pour un créneau de midi" do
      midi_event = create(:party_event, :private_party, slot: :midi)
      order = build_party_order(patons: 6, event: midi_event)

      expect(described_class.new(order).body.lines.last).to eq('Midi : Michael Hulet - 6 personnes')
    end

    it "ne compte pas la ligne forfait dans le nombre de personnes" do
      order = build_party_order(patons: 4)

      # 4 boules + 1 forfait = 5 lignes de quantité, mais 4 personnes.
      expect(order.order_items.sum(:qty)).to eq(5)
      expect(described_class.new(order).body).to end_with('- 4 personnes')
    end
  end

  describe '#to_payload' do
    it "porte la date de l'événement, le type « orange » et une référence externe stable" do
      order = build_party_order(patons: 18)

      expect(described_class.new(order).to_payload).to eq(
        date: party_event.held_on,
        color: 'orange',
        external_ref: "tranchesdevie-order-#{order.id}",
        body: "Pizza Party privée\nSoirée : Michael Hulet - 18 personnes"
      )
    end
  end
end
