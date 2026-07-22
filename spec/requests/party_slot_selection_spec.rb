require 'rails_helper'

# Sélection de la date + créneau (midi/soir) d'une Pizza party privée
# (#pizza-parties) : calendrier sur la page événements, validation à l'ajout
# panier, garde au checkout.
RSpec.describe 'Pizza party — choix de la date et du créneau', type: :request do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:party_product) do
    create(:product, :pizza_party, channel: 'store', name: 'Pizza party privée – Nombre de personnes')
  end
  let!(:party_variant) do
    create(:product_variant, product: party_product, name: 'une boule', price_cents: 500, channel: 'store')
  end
  let!(:forfait_product) { create(:product, :pizza_party_forfait, name: 'Forfait Pizza party privée') }
  let!(:forfait_variant) do
    create(:product_variant, product: forfait_product, name: 'forfait', price_cents: 4000, channel: 'store')
  end

  let(:date) { Date.current + 7 }
  let(:slot_choice) { "#{date.iso8601}|soir" }

  describe 'GET /evenements' do
    it 'affiche le calendrier des créneaux disponibles' do
      get evenements_path

      expect(response.body).to include('Choisis ta date et ton créneau')
      expect(response.body).to include("#{date.iso8601}|midi")
      expect(response.body).to include("#{date.iso8601}|soir")
    end

    it 'désactive un créneau bloqué (pas de bouton radio pour lui)' do
      create(:party_slot_block, blocked_on: date, slot: :soir)

      get evenements_path

      expect(response.body).to include("#{date.iso8601}|midi")
      expect(response.body).not_to include("#{date.iso8601}|soir")
    end
  end

  describe 'POST /cart/add (party privée)' do
    it 'stocke la date et le créneau choisis en session' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, qty: 4 }

      expect(session[:party_date]).to eq(date.iso8601)
      expect(session[:party_slot]).to eq('soir')
      expect(response).to redirect_to(cart_path)
    end

    it 'rejette un créneau indisponible (page périmée ou requête forgée)' do
      create(:party_slot_block, blocked_on: date, slot: :soir)

      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, qty: 4 }

      expect(session[:cart].to_a).to be_empty
      expect(response).to redirect_to(evenements_path)
    end

    it 'rejette une party sans date/créneau' do
      post cart_add_path, params: { product_variant_id: party_variant.id, qty: 4 }

      expect(session[:cart].to_a).to be_empty
      expect(response).to redirect_to(evenements_path)
    end

    it 'refuse de mélanger party et articles ordinaires (dans les deux sens)' do
      bread = create(:product, channel: 'store')
      bread_variant = create(:product_variant, product: bread, channel: 'store', price_cents: 700)

      # Pain déjà au panier → party refusée.
      post cart_add_path, params: { product_variant_id: bread_variant.id, qty: 1 }
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, qty: 4 }
      expect(session[:cart].map { |i| i['product_variant_id'] }).to eq([ bread_variant.id.to_s ])

      # Party au panier → pain refusé.
      session_reset = -> { delete cart_remove_path(bread_variant.id.to_s) }
      session_reset.call
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, qty: 4 }
      post cart_add_path, params: { product_variant_id: bread_variant.id, qty: 1 }
      ids = session[:cart].map { |i| i['product_variant_id'] }
      expect(ids).to contain_exactly(party_variant.id.to_s, forfait_variant.id.to_s)
    end

    it 'oublie la date choisie quand la party est retirée du panier' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, qty: 4 }
      delete cart_remove_path(party_variant.id.to_s)

      expect(session[:party_date]).to be_nil
      expect(session[:party_slot]).to be_nil
    end
  end

  describe 'GET /checkout (panier party)' do
    it 'passe sans jour de cuisson quand la date de party est valide' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, qty: 4 }

      get new_checkout_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Pizza party')
    end

    it 'renvoie vers les événements si le créneau n’est plus disponible' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, qty: 4 }
      create(:party_slot_block, blocked_on: date, slot: :soir)

      get new_checkout_path

      expect(response).to redirect_to(evenements_path)
    end
  end
end
