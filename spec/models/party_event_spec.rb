require "rails_helper"

RSpec.describe PartyEvent do
  describe ".private_slot_available?" do
    let(:date) { Date.current + 7 }

    before { ProductionSetting.current.update!(private_party_slot_capacity: 2) }

    it "est disponible par défaut (ouvert, non bloqué, sous capacité)" do
      expect(described_class.private_slot_available?(date, "soir")).to be true
    end

    it "est indisponible si le créneau est bloqué" do
      create(:party_slot_block, blocked_on: date, slot: :soir)
      expect(described_class.private_slot_available?(date, "soir")).to be false
    end

    it "est indisponible si toute la journée est bloquée (slot nil)" do
      create(:party_slot_block, blocked_on: date, slot: nil)
      expect(described_class.private_slot_available?(date, "midi")).to be false
      expect(described_class.private_slot_available?(date, "soir")).to be false
    end

    it "devient indisponible quand la capacité du créneau est atteinte" do
      2.times { create(:party_event, :private_party, held_on: date, slot: :soir) }
      expect(described_class.private_slot_available?(date, "soir")).to be false
      expect(described_class.private_slot_available?(date, "midi")).to be true # autre créneau libre
    end

    it "est indisponible pour une date passée" do
      expect(described_class.private_slot_available?(Date.current - 1, "soir")).to be false
    end

    it "est indisponible en soirée si une party publique est programmée ce jour" do
      create(:party_event, :public_party, held_on: date)
      expect(described_class.private_slot_available?(date, "soir")).to be false
      expect(described_class.private_slot_available?(date, "midi")).to be true # midi reste libre
    end

    it "ignore une party publique supprimée pour le blocage du soir" do
      event = create(:party_event, :public_party, held_on: date)
      event.soft_delete!
      expect(described_class.private_slot_available?(date, "soir")).to be true
    end

    it "ignore les événements supprimés dans le décompte de capacité" do
      2.times { create(:party_event, :private_party, held_on: date, slot: :soir) }
      described_class.private_events.first.soft_delete!
      expect(described_class.private_slot_available?(date, "soir")).to be true
    end
  end

  describe "validations" do
    it "exige un créneau pour une party privée" do
      event = build(:party_event, :private_party, slot: nil)
      expect(event).not_to be_valid
      expect(event.errors[:slot]).to be_present
    end

    it "exige un titre pour une party publique" do
      event = build(:party_event, :public_party, title: nil)
      expect(event).not_to be_valid
      expect(event.errors[:title]).to be_present
    end

    it "exige une capacité pour une party publique" do
      event = build(:party_event, :public_party, capacity: nil)
      expect(event).not_to be_valid
      expect(event.errors[:capacity]).to be_present
    end

    it "exige une clôture des inscriptions pour une party publique" do
      event = build(:party_event, :public_party, registration_closes_at: nil)
      expect(event).not_to be_valid
      expect(event.errors[:registration_closes_at]).to be_present
    end

    it "n'exige ni capacité ni clôture pour une party privée" do
      event = build(:party_event, :private_party, capacity: nil, registration_closes_at: nil)
      expect(event).to be_valid
    end
  end

  describe "#registration_open?" do
    it "est ouvert pour un événement public actif sans date de clôture" do
      expect(build(:party_event, :public_party, active: true, registration_closes_at: nil).registration_open?).to be true
    end

    it "est fermé après la date de clôture" do
      expect(build(:party_event, :public_party, registration_closes_at: 1.day.ago).registration_open?).to be false
    end
  end
end

RSpec.describe PartySlotBlock do
  it "détecte un blocage de créneau précis" do
    create(:party_slot_block, blocked_on: Date.current + 3, slot: :midi)
    expect(described_class.blocked?(Date.current + 3, "midi")).to be true
    expect(described_class.blocked?(Date.current + 3, "soir")).to be false
  end

  it "un blocage journée (slot nil) couvre les deux créneaux" do
    create(:party_slot_block, blocked_on: Date.current + 3, slot: nil)
    expect(described_class.blocked?(Date.current + 3, "midi")).to be true
    expect(described_class.blocked?(Date.current + 3, "soir")).to be true
  end
end

RSpec.describe Order, "commande party (#pizza-parties)" do
  let(:pickup) { create(:pickup_location) }

  it "accepte une commande party sans fournée mais avec party_event" do
    event = create(:party_event, :private_party)
    order = build(:order, source: :party, bake_day: nil, party_event: event, pickup_location: pickup)
    expect(order).to be_valid
  end

  it "refuse une commande party sans party_event" do
    order = build(:order, source: :party, bake_day: nil, party_event: nil, pickup_location: pickup)
    expect(order).not_to be_valid
    expect(order.errors[:party_event]).to be_present
  end

  it "refuse une commande normale sans fournée" do
    order = build(:order, source: :checkout, bake_day: nil, party_event: nil, pickup_location: pickup)
    expect(order).not_to be_valid
    expect(order.errors[:bake_day]).to be_present
  end
end
