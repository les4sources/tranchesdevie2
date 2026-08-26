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

  # Depuis #201, une party privée ne se réserve que le mardi ou le vendredi
  # SOIR. On vise le mardi de la semaine suivante : entre 8 et 14 jours, donc
  # toujours au-delà de la limite « veille 16 h », quelle que soit l'heure à
  # laquelle la suite tourne.
  let(:date) { Date.current.next_occurring(:tuesday) + 7 }
  let(:slot_choice) { "#{date.iso8601}|soir" }

  describe 'GET /evenements' do
    # Depuis #201, seul le SOIR est réservable, et seulement le mardi ou le
    # vendredi : le midi reste rendu dans le calendrier mais toujours à false.
    it 'ouvre le créneau du soir sur un mardi, jamais celui de midi' do
      get pizza_party_privee_path

      expect(response.body).to include('Choisis ta date')
      expect(response.body).to include(%(data-date="#{date.iso8601}"))
      day_button = response.body[/data-date="#{date.iso8601}".{0,200}/m]
      expect(day_button).to include('data-midi="false"')
      expect(day_button).to include('data-soir="true"')
    end

    it 'ne rend aucun bouton pour un mercredi — plus aucun créneau ouvert' do
      wednesday = date + 1

      get pizza_party_privee_path

      expect(response.body).not_to include(%(data-date="#{wednesday.iso8601}"))
    end

    it "ne rend aucun bouton pour un mardi dont le soir est bloqué" do
      create(:party_slot_block, blocked_on: date, slot: :soir)

      get pizza_party_privee_path

      expect(response.body).not_to include(%(data-date="#{date.iso8601}"))
    end

    it 'marque les jours de cuisson (four déjà chaud) via data-oven-hot' do
      get pizza_party_privee_path

      expect(response.body[/data-date="#{date.iso8601}".{0,120}/m]).to include('data-oven-hot="true"')
    end

    it 'ne rend pas de bouton pour un jour entièrement bloqué' do
      create(:party_slot_block, blocked_on: date, slot: nil)

      get pizza_party_privee_path

      expect(response.body).not_to include(%(data-date="#{date.iso8601}"))
    end
  end

  describe 'POST /cart/add (party privée)' do
    it 'stocke la date et le créneau choisis en session' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }

      expect(session[:party_date]).to eq(date.iso8601)
      expect(session[:party_slot]).to eq('soir')
      expect(response).to redirect_to(cart_path)
    end

    it 'rejette un créneau indisponible (page périmée ou requête forgée)' do
      create(:party_slot_block, blocked_on: date, slot: :soir)

      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }

      expect(session[:cart].to_a).to be_empty
      expect(response).to redirect_to(pizza_party_privee_path)
    end

    it 'rejette une party sans date/créneau' do
      post cart_add_path, params: { product_variant_id: party_variant.id, qty: 4 }

      expect(session[:cart].to_a).to be_empty
      expect(response).to redirect_to(pizza_party_privee_path)
    end

    it 'refuse de mélanger party et articles ordinaires (dans les deux sens)' do
      bread = create(:product, channel: 'store')
      bread_variant = create(:product_variant, product: bread, channel: 'store', price_cents: 700)

      # Pain déjà au panier → party refusée.
      post cart_add_path, params: { product_variant_id: bread_variant.id, qty: 1 }
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }
      expect(session[:cart].map { |i| i['product_variant_id'] }).to eq([ bread_variant.id.to_s ])

      # Party au panier → pain refusé.
      session_reset = -> { delete cart_remove_path(bread_variant.id.to_s) }
      session_reset.call
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }
      post cart_add_path, params: { product_variant_id: bread_variant.id, qty: 1 }
      ids = session[:cart].map { |i| i['product_variant_id'] }
      expect(ids).to contain_exactly(party_variant.id.to_s, forfait_variant.id.to_s)
    end

    it 'oublie la date choisie quand la party est retirée du panier' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }
      delete cart_remove_path(party_variant.id.to_s)

      expect(session[:party_date]).to be_nil
      expect(session[:party_slot]).to be_nil
    end
  end

  describe 'POST /checkout/create_wallet_order (panier party)' do
    let(:customer) { create(:customer, first_name: 'Léa') }

    before do
      allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
      allow(OtpService).to receive(:verify_code).and_return({ success: true })
      post '/connexion', params: { identifier: customer.phone_e164 }
      post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }
    end

    it 'refuse le paiement par portefeuille pour une party' do
      post '/checkout/create_wallet_order',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('portefeuille')
      expect(Order.count).to eq(0)
    end

    it 'ne propose pas l’option portefeuille au checkout party (même avec solde suffisant)' do
      wallet = create(:wallet, customer: customer, balance_cents: 100_000)

      get new_checkout_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Payer avec mon portefeuille')
      expect(wallet.balance_cents).to eq(100_000)
    end
  end

  describe 'GET /checkout (panier party)' do
    it 'passe sans jour de cuisson quand la date de party est valide' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }

      get new_checkout_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Pizza party')
    end

    it 'renvoie vers les événements si le créneau n’est plus disponible' do
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'On arrive vers 18h30.', qty: 4 }
      create(:party_slot_block, blocked_on: date, slot: :soir)

      get new_checkout_path

      expect(response).to redirect_to(pizza_party_privee_path)
    end
  end
end
