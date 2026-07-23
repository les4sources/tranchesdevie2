require 'rails_helper'

# Inscriptions aux Pizza parties PUBLIQUES (#pizza-parties) : page dédiée,
# panier rattaché à l'événement, checkout en commande party, gardes.
RSpec.describe 'Pizza party publique — inscriptions', type: :request do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:public_product) { create(:product, :pizza_party_public, channel: 'store', name: 'Pizza party publique') }
  let!(:adult_variant) do
    create(:product_variant, product: public_product, name: 'adulte', price_cents: 1_000, channel: 'store')
  end
  let!(:child_variant) do
    create(:product_variant, product: public_product, name: 'enfant', price_cents: 600, channel: 'store')
  end
  let!(:event) do
    create(:party_event, :public_party, title: 'Pizza Party de septembre',
                                        held_on: Date.current + 14, capacity: 40,
                                        registration_closes_at: 10.days.from_now)
  end

  describe 'GET /pizza-party-publique' do
    it 'liste les événements avec places restantes et clôture' do
      get pizza_parties_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Pizza Party de septembre')
      expect(response.body).to include('40 places restantes')
      expect(response.body).to include('Adulte')
      expect(response.body).to include('Enfant')
    end

    it 'masque les places restantes au-dessus de 50' do
      event.update!(capacity: 120)

      get pizza_parties_path

      expect(response.body).not_to include('places restantes')
      expect(response.body).to include('Adulte')
    end

    it 'affiche « complet » quand la jauge est atteinte' do
      customer = create(:customer)
      order = create(:order, customer: customer, party_event: event, bake_day: nil, source: :party, status: :paid)
      create(:order_item, order: order, product_variant: adult_variant, qty: 40)

      get pizza_parties_path

      expect(response.body).to include('Cet événement est complet.')
    end

    it 'affiche « clôturées » après la date de clôture' do
      event.update!(registration_closes_at: 1.hour.ago)

      get pizza_parties_path

      expect(response.body).to include('clôturées')
    end
  end

  describe 'POST /cart/add (inscription publique)' do
    it 'rattache le panier à l’événement en session' do
      post cart_add_path, params: { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 2 }
      post cart_add_path, params: { product_variant_id: child_variant.id, public_party_event_id: event.id, qty: 1 }

      expect(session[:public_party_event_id]).to eq(event.id)
      expect(session[:cart].sum { |i| i['qty'].to_i }).to eq(3)
      expect(response).to redirect_to(pizza_parties_path)
    end

    it 'refuse une inscription clôturée ou sans événement' do
      event.update!(registration_closes_at: 1.hour.ago)

      post cart_add_path, params: { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 2 }
      expect(session[:cart].to_a).to be_empty

      post cart_add_path, params: { product_variant_id: adult_variant.id, qty: 2 }
      expect(session[:cart].to_a).to be_empty
    end

    it 'refuse une quantité au-dessus des places restantes' do
      event.update!(capacity: 3)

      post cart_add_path, params: { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 4 }

      expect(session[:cart].to_a).to be_empty
      expect(flash[:alert]).to include('3 places')
    end

    it 'refuse le mixage avec du pain ou une party privée (dans les deux sens)' do
      bread = create(:product, channel: 'store')
      bread_variant = create(:product_variant, product: bread, channel: 'store', price_cents: 700)

      post cart_add_path, params: { product_variant_id: bread_variant.id, qty: 1 }
      post cart_add_path, params: { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 2 }
      expect(session[:cart].map { |i| i['product_variant_id'] }).to eq([ bread_variant.id.to_s ])

      delete cart_remove_path(bread_variant.id.to_s)
      post cart_add_path, params: { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 2 }
      post cart_add_path, params: { product_variant_id: bread_variant.id, qty: 1 }
      expect(session[:cart].map { |i| i['product_variant_id'] }).to eq([ adult_variant.id.to_s ])
    end

    it 'refuse de mélanger deux événements et oublie l’événement quand le panier se vide' do
      other = create(:party_event, :public_party, held_on: Date.current + 21, capacity: 40,
                                                  registration_closes_at: 10.days.from_now)

      post cart_add_path, params: { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 2 }
      post cart_add_path, params: { product_variant_id: child_variant.id, public_party_event_id: other.id, qty: 1 }
      expect(session[:public_party_event_id]).to eq(event.id)
      expect(session[:cart].map { |i| i['product_variant_id'] }).to eq([ adult_variant.id.to_s ])

      delete cart_remove_path(adult_variant.id.to_s)
      expect(session[:public_party_event_id]).to be_nil
    end
  end

  describe 'checkout (panier public)' do
    let(:customer) { create(:customer, first_name: 'Léa') }

    before do
      allow(OrderNotificationService).to receive(:send_confirmation)
      allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
      allow(OtpService).to receive(:verify_code).and_return({ success: true })
      post '/connexion', params: { identifier: customer.phone_e164 }
      post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
      post cart_add_path, params: { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 2 }
      post cart_add_path, params: { product_variant_id: child_variant.id, public_party_event_id: event.id, qty: 1 }
    end

    it 'passe sans jour de cuisson et récapitule l’événement' do
      get new_checkout_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Ton inscription Pizza party')
      expect(response.body).not_to include('Payer avec mon portefeuille')
    end

    it 'crée une commande party rattachée à l’événement au paiement en ligne' do
      stub_stripe_payment_intent_create(amount: (1_000 * 2) + 600)

      post '/checkout/create_payment_intent',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      order = Order.order(:created_at).last
      expect(order.source).to eq('party')
      expect(order.party_event).to eq(event)
      expect(order.bake_day).to be_nil
      expect(order.total_cents).to eq(2_600)
      expect(event.seats_taken).to eq(3)
    end

    it 'refuse le paiement quand la jauge restante est insuffisante' do
      event.update!(capacity: 2)

      post '/checkout/create_payment_intent',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('2 places')
      expect(Order.count).to eq(0)
    end

    it 'refuse le paiement par portefeuille' do
      post '/checkout/create_wallet_order',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('portefeuille')
    end

    it 'renvoie vers la page publique si les inscriptions ferment entre-temps' do
      event.update!(registration_closes_at: 1.minute.ago)

      get new_checkout_path

      expect(response).to redirect_to(pizza_parties_path)
    end
  end

  describe 'service — jauge sous verrou' do
    let(:customer) { create(:customer) }
    let(:cart) { [ { 'product_variant_id' => adult_variant.id.to_s, 'qty' => 2 } ] }

    def service
      PublicPartyRegistrationService.new(customer: customer, party_event: event, cart_items: cart)
    end

    it 'crée la commande et consomme la jauge' do
      order = service.call

      expect(order).to be_a(Order)
      expect(order.party_event).to eq(event)
      expect(event.seats_taken).to eq(2)
    end

    it 'compte les commandes pending dans la jauge mais pas les annulées' do
      pending_order = service.call
      expect(event.seats_taken).to eq(2)

      pending_order.update!(status: :cancelled)
      expect(event.reload.seats_taken).to eq(0)
    end

    it 'libère la réservation pending précédente du client avant de re-réserver' do
      event.update!(capacity: 2)
      stale = service.call
      expect(stale.status).to eq('pending')

      retry_order = service.call
      expect(retry_order).to be_a(Order)
      expect(Order.exists?(stale.id)).to be(false)
      expect(event.seats_taken).to eq(2)
    end

    it 'refuse au-delà de la jauge et après clôture' do
      event.update!(capacity: 1)
      svc = service
      expect(svc.call).to be(false)
      expect(svc.errors.join).to include('1 place')

      event.update!(capacity: 40, registration_closes_at: 1.minute.ago)
      svc = service
      expect(svc.call).to be(false)
      expect(svc.errors.join).to include('clôturées')
    end
  end

  describe 'admin — compteur d’inscrits' do
    it 'affiche inscrits / capacité' do
      customer = create(:customer)
      order = create(:order, customer: customer, party_event: event, bake_day: nil, source: :party, status: :paid)
      create(:order_item, order: order, product_variant: adult_variant, qty: 5)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ADMIN_PASSWORD').and_return('secret')
      post admin_login_path, params: { password: 'secret' }

      get admin_party_events_path

      expect(response.body).to include('Inscrits')
      expect(response.body).to include('>5<')
    end
  end
end
