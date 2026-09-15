require 'rails_helper'

# Validation d'une demande de Pizza party (#pizza-parties).
#
# La validation est le SEUL moment où la capacité du créneau est vérifiée : une
# demande n'occupe rien, donc deux groupes peuvent viser la même soirée. C'est
# ici que la boulangerie arbitre, et ici que le verrou protège l'arbitrage.
RSpec.describe PartyDecisionService do
  include ActiveSupport::Testing::TimeHelpers

  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  def build_request(suffix)
    customer = create(:customer, phone_e164: "+3247020#{suffix}", email: "groupe#{suffix}@example.com")
    create(:party_request, customer: customer)
  end

  describe "capacité du créneau" do
    before { ProductionSetting.current.update!(private_party_slot_capacity: 1) }

    it "n'en laisse passer qu'une quand il ne reste qu'une place" do
      first = build_request("1")
      second = build_request("2")

      expect(described_class.new(first, decided_by: "Romane").accept).to be_present

      service = described_class.new(second, decided_by: "Thomas")
      expect(service.accept).to be false
      expect(service.errors.join).to match(/plus disponible/)
      expect(second.reload).to be_state_pending
    end

    it "prend le verrou consultatif du créneau AVANT de juger la disponibilité" do
      request = build_request("3")
      service = described_class.new(request, decided_by: "Romane")

      ordered = []
      allow(service).to receive(:lock_slot!) { ordered << :lock }
      allow(PartyEvent).to receive(:private_slot_available?) do
        ordered << :check
        true
      end

      service.accept
      expect(ordered).to eq([ :lock, :check ])
    end
  end

  describe "conflit avec une party publique" do
    it "refuse la validation et laisse la demande en attente" do
      request = build_request("4")
      create(:party_event, :public_party, held_on: request.held_on)

      service = described_class.new(request, decided_by: "Romane")

      expect(service.accept).to be false
      expect(request.reload).to be_state_pending
      expect(PartyEvent.private_events.count).to eq(0)
    end
  end

  describe "échéance de paiement" do
    it "tombe sur le cut-off de la fournée du jour de la party" do
      request = build_request("5")
      order = described_class.new(request, decided_by: "Romane").accept

      expect(order.payment_due_at).to be_within(1.second).of(PartyRequest.cut_off_for(request.held_on))
    end

    it "laisse au moins 24 h quand la validation tombe après la sollicitation" do
      request = build_request("6")
      prompt_at = PartyRequest.payment_prompt_at(request.held_on)

      travel_to(prompt_at + 1.hour) do
        order = described_class.new(request, decided_by: "Romane").accept
        expect(order.payment_due_at).to be > Time.current
        expect(order.payment_due_at).to be <= Time.current + 24.hours
      end
    end
  end

  describe "une demande sans tarif figé" do
    it "est refusée avec un message clair plutôt qu'une erreur de validation" do
      request = build_request("7")
      request.party_request_items.destroy_all

      service = described_class.new(request.reload, decided_by: "Romane")

      expect { expect(service.accept).to be false }.not_to raise_error
      expect(service.errors.join).to match(/tarif/)
    end
  end
end
