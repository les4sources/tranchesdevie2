require 'rails_helper'

# Calendrier des disponibilités privées (#pizza-parties) : version groupée de
# private_slot_available?, une poignée de requêtes pour toute la plage.
RSpec.describe PartyEvent, '.private_availability' do
  let(:date) { Date.current + 7 }
  let(:range) { (Date.current + 1)..(Date.current + 14) }

  it 'ouvre midi et soir par défaut (dès le délai minimum d’une semaine)' do
    availability = described_class.private_availability(range)

    expect(availability[date]).to eq({ 'midi' => true, 'soir' => true })
  end

  it 'ferme les jours à moins d’une semaine (délai minimum de réservation)' do
    availability = described_class.private_availability(range)

    expect(availability[Date.current + 6]).to eq({ 'midi' => false, 'soir' => false })
    expect(described_class.private_slot_available?(Date.current + 6, 'soir')).to be(false)
  end

  it 'ferme un créneau bloqué par l’admin, et toute la journée si blocage sans créneau' do
    create(:party_slot_block, blocked_on: date, slot: :midi)
    create(:party_slot_block, blocked_on: date + 1, slot: nil)

    availability = described_class.private_availability(range)

    expect(availability[date]).to eq({ 'midi' => false, 'soir' => true })
    expect(availability[date + 1]).to eq({ 'midi' => false, 'soir' => false })
  end

  it 'ferme le soir quand une party publique occupe la date' do
    create(:party_event, :public_party, held_on: date)

    availability = described_class.private_availability(range)

    expect(availability[date]).to eq({ 'midi' => true, 'soir' => false })
  end

  it 'ferme un créneau à capacité atteinte' do
    PartyEvent.private_slot_capacity.times { create(:party_event, :private_party, held_on: date, slot: :soir) }

    availability = described_class.private_availability(range)

    expect(availability[date]).to eq({ 'midi' => true, 'soir' => false })
  end

  it 'concorde avec private_slot_available? sur toute la plage' do
    create(:party_slot_block, blocked_on: date, slot: :midi)
    create(:party_event, :public_party, held_on: date + 2)
    create(:party_event, :private_party, held_on: date + 3, slot: :midi)

    availability = described_class.private_availability(range)

    range.each do |day|
      %w[midi soir].each do |slot|
        expect(availability[day][slot]).to eq(described_class.private_slot_available?(day, slot)),
          "désaccord pour #{day} #{slot}"
      end
    end
  end
end
