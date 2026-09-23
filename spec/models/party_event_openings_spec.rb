require "rails_helper"

# Dates supplémentaires (#pizza-parties) — l'admin ouvre à la main un soir que
# la règle mardi/vendredi ignore (un samedi de groupe, un jour férié).
#
# Ce soir-là n'a pas de fournée : les pâtons sont pétris par la DERNIÈRE fournée
# avant lui. La réservation ferme donc la veille de CETTE fournée à 12 h, et non
# la veille du soir lui-même — sinon on accepterait un groupe que plus personne
# ne peut préparer.
RSpec.describe PartyOpening, "dates supplémentaires des parties privées" do
  include ActiveSupport::Testing::TimeHelpers

  let(:friday)   { Date.new(2026, 9, 25) }
  let(:saturday) { Date.new(2026, 9, 26) }
  let(:monday)   { Date.new(2026, 9, 28) }

  def travel_to_brussels(date, hour, minute = 0)
    travel_to(ActiveSupport::TimeZone["Europe/Brussels"].local(date.year, date.month, date.day, hour, minute))
  end

  def brussels(date, hour)
    ActiveSupport::TimeZone["Europe/Brussels"].local(date.year, date.month, date.day, hour, 0, 0)
  end

  before { travel_to_brussels(Date.new(2026, 9, 1), 10) }
  after { travel_back }

  describe "ouverture d'un soir" do
    it "un samedi fermé par la règle devient réservable une fois ouvert" do
      expect(PartyEvent.private_slot_available?(saturday, "soir")).to be false

      PartyOpening.create!(opened_on: saturday)

      expect(PartyEvent.private_bookable_slot?(saturday, "soir")).to be true
      expect(PartyEvent.private_slot_available?(saturday, "soir")).to be true
      expect(PartyRequest.requestable?(saturday, "soir")).to be true
    end

    it "n'ouvre jamais le midi" do
      PartyOpening.create!(opened_on: saturday)

      expect(PartyEvent.private_bookable_slot?(saturday, "midi")).to be false
    end

    it "retirer l'ouverture referme le soir" do
      opening = PartyOpening.create!(opened_on: saturday)
      opening.destroy

      expect(PartyEvent.private_slot_available?(saturday, "soir")).to be false
    end

    it "refuse deux ouvertures pour la même date" do
      PartyOpening.create!(opened_on: saturday)

      expect(PartyOpening.new(opened_on: saturday)).not_to be_valid
    end

    it "signale une ouverture posée un jour de boulangerie comme sans effet" do
      expect(PartyOpening.new(opened_on: friday)).to be_redundant
      expect(PartyOpening.new(opened_on: saturday)).not_to be_redundant
    end
  end

  describe "les autres règles s'appliquent toujours" do
    before { PartyOpening.create!(opened_on: saturday) }

    it "un blocage ferme le soir ouvert" do
      PartySlotBlock.create!(blocked_on: saturday, slot: nil)

      expect(PartyEvent.private_slot_available?(saturday, "soir")).to be false
    end

    it "une party publique ce soir-là le ferme" do
      create(:party_event, :public_party, held_on: saturday)

      expect(PartyEvent.private_slot_available?(saturday, "soir")).to be false
    end
  end

  describe "délai de réservation : la veille de la fournée qui pétrit" do
    it "un samedi ferme le jeudi à 12 h (fournée du vendredi)" do
      expect(PartyEvent.private_preparation_date(saturday)).to eq(friday)
      expect(PartyEvent.private_booking_deadline(saturday)).to eq(brussels(friday.prev_day, 12))
    end

    it "un lundi remonte aussi au vendredi précédent" do
      expect(PartyEvent.private_preparation_date(monday)).to eq(friday)
    end

    it "une fournée exceptionnelle plus proche que la règle la remplace" do
      # Pas de vendredi cette semaine-là : une fournée le samedi matin même.
      create(:bake_day, baked_on: saturday, cut_off_at: brussels(friday, 12))

      expect(PartyEvent.private_preparation_date(saturday)).to eq(saturday)
      expect(PartyEvent.private_preparation_date(saturday, bake_dates: Set[saturday])).to eq(saturday)
    end

    # Régression vue en dev : la fournée du vendredi n'était pas encore créée, et
    # le calcul remontait à celle de la semaine d'avant — la réservation fermait
    # une semaine trop tôt.
    it "une fournée pas encore créée ne recule pas la préparation d'une semaine" do
      previous_friday = friday - 7
      create(:bake_day, baked_on: previous_friday, cut_off_at: brussels(previous_friday.prev_day, 12))

      expect(PartyEvent.private_preparation_date(saturday)).to eq(friday)
      expect(PartyEvent.private_preparation_date(saturday, bake_dates: Set[previous_friday])).to eq(friday)
    end

    it "est fermé à 12 h 01 la veille de la fournée, alors que le soir est à deux jours" do
      PartyOpening.create!(opened_on: saturday)

      travel_to_brussels(friday.prev_day, 11, 59)
      expect(PartyEvent.private_slot_available?(saturday, "soir")).to be true

      travel_to_brussels(friday.prev_day, 12, 1)
      expect(PartyEvent.private_slot_available?(saturday, "soir")).to be false
    end

    it "le cut-off de la demande est celui de la fournée du vendredi" do
      expect(PartyRequest.cut_off_for(saturday)).to eq(BakeDay.calculate_cut_off_for(friday))
    end
  end

  describe "calendriers (calcul groupé)" do
    before { PartyOpening.create!(opened_on: saturday) }

    it "le calendrier de réservation dit la même chose que la vérification à l'unité" do
      range = Date.new(2026, 9, 21)..Date.new(2026, 10, 4)
      map = PartyEvent.private_availability(range)

      range.each do |date|
        expect(map[date]["soir"]).to eq(PartyEvent.private_slot_available?(date, "soir")), date.to_s
      end
      expect(map[saturday]["soir"]).to be true
      expect(map[Date.new(2026, 10, 3)]["soir"]).to be false
    end

    it "le calendrier de demande ouvre le samedi" do
      range = Date.new(2026, 9, 21)..Date.new(2026, 10, 4)

      expect(PartyRequest.requestable_availability(range)[saturday]["soir"]).to be true
    end
  end
end
