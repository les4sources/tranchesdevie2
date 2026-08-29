require "rails_helper"

# #201 — les parties privées ne se réservent plus que le mardi soir et le
# vendredi soir, jusqu'à la veille 16 h (Europe/Brussels).
#
# La raison est physique, pas administrative : mardi et vendredi sont les jours
# de boulangerie, le four y est déjà chaud, et un groupe qui le chauffe lui-même
# l'abîme. Le midi est exclu parce que la fournée est en cours.
RSpec.describe PartyEvent, "règles des parties privées" do
  # Inclus localement plutôt que dans `rails_helper` : aucun autre spec du
  # projet ne voyage dans le temps aujourd'hui, autant ne pas modifier la
  # configuration partagée pour un seul fichier.
  include ActiveSupport::Testing::TimeHelpers

  # Un mardi et un vendredi bien réels, hors changement d'heure.
  let(:tuesday) { Date.new(2026, 9, 8) }
  let(:friday)  { Date.new(2026, 9, 11) }
  let(:wednesday) { Date.new(2026, 9, 9) }

  # Deux jours avant le mardi : bien avant la limite de la veille 16 h.
  def travel_to_brussels(date, hour, minute = 0)
    travel_to(ActiveSupport::TimeZone["Europe/Brussels"].local(date.year, date.month, date.day, hour, minute))
  end

  before { travel_to_brussels(Date.new(2026, 9, 1), 10) }
  after { travel_back }

  describe ".private_bookable_slot?" do
    it "accepte le mardi soir et le vendredi soir" do
      expect(described_class.private_bookable_slot?(tuesday, "soir")).to be true
      expect(described_class.private_bookable_slot?(friday, "soir")).to be true
    end

    it "refuse le créneau de midi, même un mardi" do
      expect(described_class.private_bookable_slot?(tuesday, "midi")).to be false
      expect(described_class.private_bookable_slot?(friday, "midi")).to be false
    end

    it "refuse tous les autres jours de la semaine" do
      (0..6).reject { |wday| [ 2, 5 ].include?(wday) }.each do |wday|
        date = Date.new(2026, 9, 7) + ((wday - 1) % 7)
        expect(described_class.private_bookable_slot?(date, "soir"))
          .to eq([ 2, 5 ].include?(date.wday)), "#{date} (wday #{date.wday})"
      end
    end
  end

  describe ".private_slot_available?" do
    it "est vrai pour un mardi soir libre et un vendredi soir libre" do
      expect(described_class.private_slot_available?(tuesday, "soir")).to be true
      expect(described_class.private_slot_available?(friday, "soir")).to be true
    end

    it "est faux pour le midi et pour un mercredi" do
      expect(described_class.private_slot_available?(tuesday, "midi")).to be false
      expect(described_class.private_slot_available?(wednesday, "soir")).to be false
    end

    context "les règles existantes continuent de fermer un créneau" do
      it "un blocage admin" do
        PartySlotBlock.create!(blocked_on: tuesday, slot: "soir")

        expect(described_class.private_slot_available?(tuesday, "soir")).to be false
      end

      it "un blocage admin sur toute la journée" do
        PartySlotBlock.create!(blocked_on: tuesday, slot: nil)

        expect(described_class.private_slot_available?(tuesday, "soir")).to be false
      end

      it "une party publique le même soir" do
        create(:party_event, :public_party, held_on: tuesday)

        expect(described_class.private_slot_available?(tuesday, "soir")).to be false
      end

      it "la capacité du créneau atteinte" do
        capacity = described_class.private_slot_capacity
        capacity.times { create(:party_event, :private_party, held_on: tuesday, slot: "soir") }

        expect(described_class.private_slot_available?(tuesday, "soir")).to be false
      end
    end
  end

  # La règle est celle de la boulangerie, pas celle du serveur : elle est ancrée
  # sur Europe/Brussels et doit suivre l'heure d'été.
  describe "la limite de la veille à 16 h 00, heure de Bruxelles" do
    it "est encore ouverte à 15 h 59 la veille" do
      travel_to_brussels(tuesday.prev_day, 15, 59)

      expect(described_class.private_booking_open?(tuesday)).to be true
      expect(described_class.private_slot_available?(tuesday, "soir")).to be true
    end

    it "est fermée à 16 h 01 la veille" do
      travel_to_brussels(tuesday.prev_day, 16, 1)

      expect(described_class.private_booking_open?(tuesday)).to be false
      expect(described_class.private_slot_available?(tuesday, "soir")).to be false
    end

    it "est fermée à 16 h 00 pile — la limite est stricte" do
      travel_to_brussels(tuesday.prev_day, 16, 0)

      expect(described_class.private_booking_open?(tuesday)).to be false
    end

    it "est fermée le jour même" do
      travel_to_brussels(tuesday, 9)

      expect(described_class.private_slot_available?(tuesday, "soir")).to be false
    end

    # Le 25/10/2026, Bruxelles repasse à UTC+1. Une limite calculée en UTC
    # dériverait d'une heure : ancrée sur le fuseau nommé, elle ne bouge pas.
    context "autour du changement d'heure" do
      it "tient en heure d'ÉTÉ (UTC+2) — vendredi 25/09/2026" do
        target = Date.new(2026, 9, 25)
        deadline = described_class.private_booking_deadline(target)

        expect(target.wday).to eq(5)
        expect(deadline.utc_offset).to eq(2 * 3600)
        expect(deadline.utc).to eq(Time.utc(2026, 9, 24, 14, 0, 0))
      end

      it "tient en heure d'HIVER (UTC+1) — vendredi 06/11/2026" do
        target = Date.new(2026, 11, 6)
        deadline = described_class.private_booking_deadline(target)

        expect(target.wday).to eq(5)
        expect(deadline.utc_offset).to eq(3600)
        expect(deadline.utc).to eq(Time.utc(2026, 11, 5, 15, 0, 0))
      end

      it "reste ouverte à 15 h 59 locale des deux côtés du changement" do
        [ Date.new(2026, 9, 25), Date.new(2026, 11, 6) ].each do |target|
          travel_to_brussels(target.prev_day, 15, 59)
          expect(described_class.private_booking_open?(target)).to be(true), "ouvert le #{target}"

          travel_to_brussels(target.prev_day, 16, 1)
          expect(described_class.private_booking_open?(target)).to be(false), "fermé le #{target}"
        end
      end
    end
  end

  describe ".private_availability (le calendrier)" do
    it "n'ouvre que des mardis et vendredis soir" do
      range = tuesday..(tuesday + 13)
      availability = described_class.private_availability(range)

      open_dates = availability.select { |_date, slots| slots["soir"] }.keys
      expect(open_dates).to all(satisfy { |date| [ 2, 5 ].include?(date.wday) })
      expect(open_dates).to include(tuesday, friday)
    end

    it "ne propose jamais le créneau de midi" do
      availability = described_class.private_availability(tuesday..(tuesday + 13))

      expect(availability.values.map { |slots| slots["midi"] }.uniq).to eq([ false ])
    end

    it "dit la même chose que la vérification unitaire" do
      range = tuesday..(tuesday + 13)
      availability = described_class.private_availability(range)

      range.each do |date|
        described_class::SLOT_LABELS.each_key do |slot|
          expect(availability[date][slot])
            .to eq(described_class.private_slot_available?(date, slot)), "#{date} #{slot}"
        end
      end
    end
  end

  # Non-régression : la règle ne vaut que pour la RÉSERVATION. Les événements
  # déjà en base sur d'autres jours ou à midi restent entiers.
  describe "les parties privées existantes hors règle" do
    let!(:legacy_midi) { create(:party_event, :private_party, held_on: wednesday, slot: "midi") }

    it "restent lisibles, non supprimées et comptabilisées" do
      expect(legacy_midi.reload).to be_persisted
      expect(legacy_midi.slot).to eq("midi")
      expect(described_class.private_events.not_deleted).to include(legacy_midi)
      expect(legacy_midi.slot_label).to eq("Midi")
    end

    it "occupent toujours leur créneau vis-à-vis de la capacité" do
      counted = described_class.private_events.not_deleted.where(held_on: wednesday, slot: "midi").count

      expect(counted).to eq(1)
    end
  end
end
