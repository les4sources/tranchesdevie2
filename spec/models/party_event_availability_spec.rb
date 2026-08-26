require 'rails_helper'

# Calendrier des disponibilités privées (#pizza-parties) : version groupée de
# private_slot_available?, une poignée de requêtes pour toute la plage.
#
# Depuis #201, seuls le mardi et le vendredi SOIR sont réservables : le midi est
# toujours fermé, et les autres jours aussi.
RSpec.describe PartyEvent, '.private_availability' do
  let(:tuesday) { Date.current.next_occurring(:tuesday) + 7 }
  let(:friday) { tuesday + 3 }
  let(:wednesday) { tuesday + 1 }
  let(:range) { (tuesday - 2)..(tuesday + 12) }

  it 'ouvre le soir du mardi et du vendredi, jamais le midi' do
    availability = described_class.private_availability(range)

    expect(availability[tuesday]).to eq({ 'midi' => false, 'soir' => true })
    expect(availability[friday]).to eq({ 'midi' => false, 'soir' => true })
  end

  it 'ferme tous les autres jours de la semaine' do
    availability = described_class.private_availability(range)

    expect(availability[wednesday]).to eq({ 'midi' => false, 'soir' => false })
    range.reject { |day| [ 2, 5 ].include?(day.wday) }.each do |day|
      expect(availability[day].values).to all(be(false)), "#{day} (wday #{day.wday}) devrait être fermé"
    end
  end

  it 'ferme le soir bloqué par l’admin, et la journée entière si blocage sans créneau' do
    create(:party_slot_block, blocked_on: tuesday, slot: :soir)
    create(:party_slot_block, blocked_on: friday, slot: nil)

    availability = described_class.private_availability(range)

    expect(availability[tuesday]).to eq({ 'midi' => false, 'soir' => false })
    expect(availability[friday]).to eq({ 'midi' => false, 'soir' => false })
  end

  it 'ferme le soir quand une party publique occupe la date' do
    create(:party_event, :public_party, held_on: tuesday)

    availability = described_class.private_availability(range)

    expect(availability[tuesday]).to eq({ 'midi' => false, 'soir' => false })
  end

  it 'ferme un créneau à capacité atteinte' do
    PartyEvent.private_slot_capacity.times { create(:party_event, :private_party, held_on: tuesday, slot: :soir) }

    availability = described_class.private_availability(range)

    expect(availability[tuesday]).to eq({ 'midi' => false, 'soir' => false })
  end

  it 'concorde avec private_slot_available? sur toute la plage' do
    create(:party_slot_block, blocked_on: tuesday, slot: :soir)
    create(:party_event, :public_party, held_on: friday)
    create(:party_event, :private_party, held_on: tuesday + 7, slot: :soir)

    availability = described_class.private_availability(range)

    range.each do |day|
      %w[midi soir].each do |slot|
        expect(availability[day][slot]).to eq(described_class.private_slot_available?(day, slot)),
          "désaccord pour #{day} #{slot}"
      end
    end
  end
end
