require "rails_helper"

# #203 — inscriptions ajoutées à la main sur une party publique.
#
# La démonstration centrale : une inscription manuelle PAYÉE produit exactement
# le même revenu qu'une inscription en ligne équivalente. Elle passe par le même
# `PartyOrderCreationService`, donc l'égalité est structurelle, pas recopiée.
RSpec.describe ManualPartyRegistrationService do
  let(:date) { Date.new(2026, 9, 4) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let(:product) { create(:product, :pizza_party_public, name: "Pizza party publique") }
  let!(:adulte) { create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300, flour_quantity: 200) }
  let!(:enfant) { create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200, flour_quantity: 200) }

  let!(:event) { create(:party_event, :public_party, held_on: date, capacity: 30) }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: date - 30)
    create(:variant_cost_price, product_variant: enfant, amount_cents: 26, active_from: date - 30)
  end

  def add(adults: 0, children: 0, name: "Fabienne Renard", paid: true, **rest)
    described_class.new(party_event: event, adults: adults, children: children, name: name, paid: paid, **rest).call
  end

  describe "l'ajout" do
    it "crée une inscription de 2 adultes et 1 enfant, marquée manuelle" do
      order = add(adults: 2, children: 1)

      expect(order).to be_a(Order)
      expect(order.manually_added?).to be true
      expect(order.source).to eq("party")
      expect(order.party_event).to eq(event)
      expect(order.total_cents).to eq(2 * 1_000 + 600)
      expect(order.order_items.sum(&:qty)).to eq(3)
    end

    it "crée un client à partir du seul nom, sans téléphone ni e-mail" do
      order = add(adults: 1, name: "Sans Téléphone")

      expect(order.customer.first_name).to eq("Sans")
      expect(order.customer.last_name).to eq("Téléphone")
      expect(order.customer.phone_e164).to be_nil
    end

    it "réutilise un client existant reconnu à son téléphone" do
      existing = create(:customer, phone_e164: "+32470111222")

      order = add(adults: 1, phone: "+32470111222")

      expect(order.customer).to eq(existing)
    end

    it "refuse une inscription sans nom, et sans participant" do
      service = described_class.new(party_event: event, adults: 1, children: 0, name: "")
      expect(service.call).to be false
      expect(service.errors.join).to include("nom")

      service = described_class.new(party_event: event, adults: 0, children: 0, name: "Fabienne")
      expect(service.call).to be false
      expect(service.errors.join).to include("adulte ou un enfant")
    end

    it "refuse sur un événement historique importé en agrégé" do
      historical = create(:party_event, :public_party, held_on: date,
                                        historical_source: "BilletWeb", historical_adults: 20,
                                        historical_children: 5, historical_fees_cents: 0, historical_sourciers: 0)

      service = described_class.new(party_event: historical, adults: 2, name: "Fabienne")

      expect(service.call).to be false
      expect(service.errors.join).to include("historique")
    end
  end

  describe "les totaux de l'événement" do
    it "comptent l'inscription manuelle dans la jauge" do
      expect { add(adults: 2, children: 1) }.to change { event.reload.seats_taken }.by(3)
      expect(event.seats_remaining).to eq(27)
    end

    it "comptent aussi une inscription NON payée — la place est prise" do
      expect { add(adults: 2, paid: false) }.to change { event.reload.seats_taken }.by(2)
    end
  end

  # ---- Le cœur de l'issue : l'équivalence de revenu ----
  describe "revenus" do
    # Une inscription EN LIGNE de référence, créée par le service public.
    def online(adults:, children: 0)
      customer = create(:customer)
      items = []
      items << { "product_variant_id" => adulte.id.to_s, "qty" => adults.to_s } if adults.positive?
      items << { "product_variant_id" => enfant.id.to_s, "qty" => children.to_s } if children.positive?

      order = PublicPartyRegistrationService.new(
        customer: customer, party_event: event, cart_items: items, payment_method: "cash"
      ).call
      order.update!(status: :paid)
      order
    end

    it "une inscription manuelle PAYÉE rapporte exactement autant qu'une inscription en ligne" do
      manual = add(adults: 2, children: 1, paid: true)
      web = online(adults: 2, children: 1)

      manual_result = PublicPartyRevenueService.call([ manual ])
      web_result = PublicPartyRevenueService.call([ web ])

      expect(manual_result.persons).to eq(web_result.persons)
      expect(manual_result.sale_cents).to eq(web_result.sale_cents)
      expect(manual_result.dough_cost_cents).to eq(web_result.dough_cost_cents)
      expect(manual_result.bakers_cents).to eq(web_result.bakers_cents)
      expect(manual_result.four_sources_cents).to eq(web_result.four_sources_cents)

      # Et les chiffres du barème public, en clair : 2 adultes + 1 enfant.
      expect(manual_result.bakers_cents).to eq(2 * 472 + 262)
      expect(manual_result.four_sources_cents).to eq(2 * 502 + 312)
    end

    it "une inscription manuelle NON payée ne rapporte rien" do
      manual = add(adults: 2, children: 1, paid: false)

      expect(manual.status).to eq("unpaid")
      expect(Order.completed).not_to include(manual)
      expect(PublicPartyRevenueService.call(Order.completed.where(id: manual.id)).sale_cents).to eq(0)
    end

    it "bascule non payée → payée et se met à comptabiliser" do
      manual = add(adults: 2, paid: false)

      expect(PublicPartyRevenueService.call(Order.completed.where(id: manual.id)).bakers_cents).to eq(0)

      described_class.toggle_paid(manual, paid: true)

      expect(manual.reload.paid?).to be true
      expect(manual.paid_at).to be_present
      expect(PublicPartyRevenueService.call(Order.completed.where(id: manual.id)).bakers_cents).to eq(2 * 472)
    end

    it "bascule payée → non payée et cesse de comptabiliser" do
      manual = add(adults: 2, paid: true)
      described_class.toggle_paid(manual, paid: false)

      expect(manual.reload.paid?).to be false
      expect(manual.paid_at).to be_nil
      expect(PublicPartyRevenueService.call(Order.completed.where(id: manual.id)).bakers_cents).to eq(0)
    end
  end

  describe "la modification" do
    it "recalcule le total et les places" do
      manual = add(adults: 2, children: 1)

      described_class.new(party_event: event, order: manual, adults: 1, children: 0,
                          name: "Fabienne Renard", paid: true).call

      expect(manual.reload.total_cents).to eq(1_000)
      expect(manual.order_items.sum(&:qty)).to eq(1)
      expect(event.reload.seats_taken).to eq(1)
    end
  end

  describe "la suppression" do
    it "libère les places et retire le revenu" do
      manual = add(adults: 3)
      expect(event.reload.seats_taken).to eq(3)

      manual.destroy!

      expect(event.reload.seats_taken).to eq(0)
      expect(PublicPartyRevenueService.call(Order.completed.where(party_event: event)).sale_cents).to eq(0)
    end
  end
end
