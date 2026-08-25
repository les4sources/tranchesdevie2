require "rails_helper"

# Fournée qui prépare les pâtons d'une Pizza party privée (#170).
#
# Dates fixes et explicites : le 01/09/2026 est un mardi, le 04/09 un vendredi,
# le 05/09 un samedi — soit deux jours de boulangerie encadrant un jour creux.
RSpec.describe PartyEvent, "#preparation_bake_day" do
  let(:tuesday)  { Date.new(2026, 9, 1) }
  let(:friday)   { Date.new(2026, 9, 4) }
  let(:saturday) { Date.new(2026, 9, 5) }

  let!(:tuesday_bake) { create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days) }
  let!(:friday_bake)  { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  def private_party(held_on:, slot:)
    create(:party_event, :private_party, held_on: held_on, slot: slot)
  end

  it "sert une party du SOIR par la fournée du jour même" do
    party = private_party(held_on: friday, slot: :soir)

    expect(party.preparation_bake_day).to eq(friday_bake)
  end

  it "sert une party de MIDI par la fournée précédente — la pâte n'est pas prête le matin" do
    party = private_party(held_on: friday, slot: :midi)

    expect(party.preparation_bake_day).to eq(tuesday_bake)
  end

  it "sert une party un jour SANS fournée par la dernière fournée qui précède" do
    party = private_party(held_on: saturday, slot: :soir)

    expect(party.preparation_bake_day).to eq(friday_bake)
  end

  it "renvoie nil, sans lever, quand aucune fournée ne précède la party" do
    orphan = private_party(held_on: Date.new(2026, 1, 5), slot: :soir)

    expect { @result = orphan.preparation_bake_day }.not_to raise_error
    expect(@result).to be_nil
  end

  it "ne concerne pas les parties publiques" do
    public_event = create(:party_event, :public_party, held_on: friday)

    expect(public_event.preparation_bake_day).to be_nil
  end

  describe ".prepared_by — la réciproque, en une requête" do
    it "réunit exactement les parties que la fournée doit préparer" do
      friday_evening = private_party(held_on: friday, slot: :soir)
      friday_noon    = private_party(held_on: friday, slot: :midi)
      saturday_party = private_party(held_on: saturday, slot: :soir)
      tuesday_evening = private_party(held_on: tuesday, slot: :soir)

      expect(described_class.prepared_by(friday_bake)).to contain_exactly(friday_evening, saturday_party)
      expect(described_class.prepared_by(tuesday_bake)).to contain_exactly(tuesday_evening, friday_noon)
    end

    it "est cohérente avec preparation_bake_day pour chaque party" do
      parties = [
        private_party(held_on: friday, slot: :soir),
        private_party(held_on: friday, slot: :midi),
        private_party(held_on: saturday, slot: :soir),
        private_party(held_on: tuesday, slot: :midi)
      ]

      parties.each do |party|
        expected = party.preparation_bake_day
        next if expected.nil?

        expect(described_class.prepared_by(expected)).to include(party),
          "#{party.held_on} #{party.slot} devrait être préparée par la fournée du #{expected.baked_on}"
      end
    end

    it "ignore les parties publiques" do
      create(:party_event, :public_party, held_on: friday)

      expect(described_class.prepared_by(friday_bake)).to be_empty
    end

    it "prend tout ce qui suit quand la fournée n'a pas de successeur" do
      late = private_party(held_on: Date.new(2026, 9, 20), slot: :midi)

      expect(described_class.prepared_by(friday_bake)).to include(late)
    end

    it "ne renvoie rien pour une fournée sans date" do
      expect(described_class.prepared_by(BakeDay.new)).to be_empty
      expect(described_class.prepared_by(nil)).to be_empty
    end
  end
end
