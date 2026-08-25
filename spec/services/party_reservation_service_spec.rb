require 'rails_helper'

# Réservation client d'une pizza party privée : création atomique de
# l'événement privé + sa commande, avec revalidation de la disponibilité.
RSpec.describe PartyReservationService do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:party_product) { create(:product, :pizza_party, channel: 'store') }
  let!(:party_variant) do
    create(:product_variant, product: party_product, name: 'une boule', price_cents: 500, channel: 'store')
  end
  let(:customer) { create(:customer) }
  let(:date) { Date.current + 7 }
  let(:cart) { [ { 'product_variant_id' => party_variant.id.to_s, 'qty' => 4 } ] }

  # Le commentaire client est obligatoire depuis #169 : le helper en fournit un
  # par défaut, pour que les exemples qui testent autre chose restent lisibles.
  def service(slot: 'soir', customer_note: 'On arrive vers 18h30, anniversaire de Jules.', **options)
    described_class.new(customer: customer, date: date.iso8601, slot: slot, cart_items: cart,
                        customer_note: customer_note, **options)
  end

  describe 'commentaire du client (#169)' do
    it 'persiste le commentaire sur la commande créée' do
      order = service(customer_note: 'On arrive vers 18h30, anniversaire de Jules.').call

      expect(order.customer_note).to eq('On arrive vers 18h30, anniversaire de Jules.')
    end

    it 'refuse une réservation sans commentaire, sans rien créer' do
      svc = service(customer_note: nil)

      expect { expect(svc.call).to be(false) }.not_to change(Order, :count)
      expect(svc.errors.join).to include('ton groupe')
    end

    it "refuse un commentaire fait uniquement d'espaces" do
      svc = service(customer_note: "  \n ")

      expect(svc.call).to be(false)
      expect(svc.errors.join).to include('ton groupe')
    end

    it 'refuse un commentaire de plus de 500 caractères' do
      svc = service(customer_note: 'a' * 501)

      expect { expect(svc.call).to be(false) }.not_to change(PartyEvent, :count)
      expect(svc.errors.join).to include('500')
    end

    it 'accepte 500 caractères pile' do
      expect(service(customer_note: 'a' * 500).call.customer_note.length).to eq(500)
    end

    it 'détoure les espaces autour du commentaire' do
      order = service(customer_note: "   Un mot   ").call

      expect(order.customer_note).to eq('Un mot')
    end
  end

  it 'crée un PartyEvent privé et sa commande party' do
    order = service.call

    expect(order).to be_a(Order)
    expect(order.source).to eq('party')
    expect(order.bake_day).to be_nil
    expect(order.party_event).to have_attributes(kind: 'private_party', held_on: date, slot: 'soir')
    expect(order.total_cents).to eq(500 * 4)
  end

  it 'refuse un créneau bloqué par l’admin' do
    create(:party_slot_block, blocked_on: date, slot: :soir)

    svc = service
    expect(svc.call).to be(false)
    expect(svc.errors.join).to include('plus disponible')
    expect(PartyEvent.private_events.count).to eq(0)
    expect(Order.count).to eq(0)
  end

  it 'refuse quand la capacité du créneau est atteinte' do
    capacity = PartyEvent.private_slot_capacity
    capacity.times { create(:party_event, :private_party, held_on: date, slot: :soir) }

    svc = service
    expect(svc.call).to be(false)
    expect(svc.errors.join).to include('plus disponible')
  end

  it 'refuse une date ou un créneau invalide' do
    svc = described_class.new(customer: customer, date: 'n’importe quoi', slot: 'soir', cart_items: cart,
                              customer_note: 'Un mot pour l’équipe.')
    expect(svc.call).to be(false)
    expect(svc.errors.join).to include('invalide')

    svc = service(slot: 'minuit')
    expect(svc.call).to be(false)
    expect(svc.errors.join).to include('invalide')
  end

  it 'libère la réservation :pending précédente du client (sans PI) avant de re-réserver' do
    stale = service.call
    expect(stale.status).to eq('pending')

    # Capacité 2 par défaut : une 2e party d'un AUTRE client occupe l'autre place.
    create(:party_event, :private_party, held_on: date, slot: :soir)

    retry_order = service.call
    expect(retry_order).to be_a(Order)
    expect(Order.exists?(stale.id)).to be(false)
    # L'événement de la réservation libérée ne survit pas (pas de fantôme de capacité).
    expect(PartyEvent.private_events.not_deleted.where(held_on: date).count).to eq(2)
  end

  it 'détruit l’événement privé orphelin quand la commande est détruite' do
    order = service.call
    event = order.party_event

    order.destroy

    expect(PartyEvent.exists?(event.id)).to be(false)
  end
end
