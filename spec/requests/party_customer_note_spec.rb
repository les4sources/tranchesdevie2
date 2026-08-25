require 'rails_helper'

# Commentaire libre obligatoire sur une réservation de Pizza party privée (#169).
RSpec.describe 'Pizza party privée — commentaire du client', type: :request do
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

  let(:slot_choice) { "#{(Date.current + 8).iso8601}|soir" }
  let(:note) { "On arrive vers 18h30 pour l'anniversaire de Jules. 8 adultes, 3 enfants, un sans gluten." }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })
  end

  def sign_in(customer)
    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
  end

  def add_party_to_cart(party_note: note, qty: 4)
    post cart_add_path, params: {
      product_variant_id: party_variant.id, party_slot_choice: slot_choice,
      qty: qty, party_note: party_note
    }
  end

  describe 'POST /cart/add' do
    it 'stocke le commentaire en session' do
      add_party_to_cart

      expect(session[:party_note]).to eq(note)
      expect(session[:party_date]).to be_present
    end

    it 'refuse une réservation sans commentaire et ne met rien au panier' do
      add_party_to_cart(party_note: nil)

      expect(session[:cart]).to be_blank
      expect(session[:party_date]).to be_blank
      expect(session[:party_note]).to be_blank
      expect(flash[:alert]).to include('ton groupe')
    end

    it "refuse un commentaire fait uniquement d'espaces" do
      add_party_to_cart(party_note: "   \n  ")

      expect(session[:cart]).to be_blank
      expect(flash[:alert]).to include('ton groupe')
    end

    it 'refuse un commentaire de plus de 500 caractères' do
      add_party_to_cart(party_note: 'a' * 501)

      expect(session[:cart]).to be_blank
      expect(flash[:alert]).to include('500')
    end

    it 'accepte un commentaire de très exactement 500 caractères' do
      add_party_to_cart(party_note: 'a' * 500)

      expect(session[:party_note]).to eq('a' * 500)
    end

    it "nettoie le commentaire quand la party sort du panier — pas de fantôme" do
      add_party_to_cart
      expect(session[:party_note]).to be_present

      delete cart_remove_path(party_variant.id.to_s)

      expect(session[:party_note]).to be_blank
      expect(session[:party_date]).to be_blank
    end
  end

  describe 'persistance sur la commande' do
    let(:customer) { create(:customer, first_name: 'Léa', email: 'lea@example.com') }

    it 'enregistre le commentaire sur la commande payée en ligne' do
      sign_in(customer)
      add_party_to_cart
      stub_stripe_payment_intent_create(amount: (500 * 4) + 4000)

      post '/checkout/create_payment_intent',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(Order.order(:created_at).last.customer_note).to eq(note)
    end

    it 'enregistre le commentaire sur une commande cash' do
      cash_customer = create(:customer, first_name: 'Yann', email: 'yann@example.com', cash_payment_allowed: true)
      sign_in(cash_customer)
      add_party_to_cart

      post '/checkout/create_cash_order',
           params: { first_name: 'Yann' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(Order.order(:created_at).last.customer_note).to eq(note)
    end

    it 'retient la correction apportée au checkout plutôt que la valeur du panier' do
      sign_in(customer)
      add_party_to_cart
      stub_stripe_payment_intent_create(amount: (500 * 4) + 4000)

      post '/checkout/create_payment_intent',
           params: { first_name: 'Léa', customer_note: 'Finalement on arrive à 19h.' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(Order.order(:created_at).last.customer_note).to eq('Finalement on arrive à 19h.')
    end

    it "rejette une requête forgée qui viderait le commentaire au paiement" do
      sign_in(customer)
      add_party_to_cart
      stub_stripe_payment_intent_create(amount: (500 * 4) + 4000)

      expect {
        post '/checkout/create_payment_intent',
             params: { first_name: 'Léa', customer_note: '' }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      }.not_to change(Order, :count)

      expect(response).not_to have_http_status(:ok)
    end

    it 'nettoie le commentaire de la session après une commande cash aboutie' do
      cash_customer = create(:customer, first_name: 'Yann', email: 'yann@example.com', cash_payment_allowed: true)
      sign_in(cash_customer)
      add_party_to_cart

      post '/checkout/create_cash_order',
           params: { first_name: 'Yann' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(session[:party_note]).to be_blank
    end
  end

  describe 'affichage' do
    let(:customer) { create(:customer, first_name: 'Léa', email: 'lea@example.com', cash_payment_allowed: true) }

    def create_party_order
      sign_in(customer)
      add_party_to_cart
      post '/checkout/create_cash_order',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }
      Order.order(:created_at).last
    end

    it 'montre le commentaire au client sur sa page de commande' do
      order = create_party_order

      get order_path(order.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Ce que tu nous as dit')
      expect(response.body).to include(CGI.escapeHTML(note))
    end

    it "montre le commentaire dans l'e-mail de confirmation" do
      order = create_party_order

      mail = OrderMailer.confirmation(order)
      body = [ mail.html_part&.body&.decoded, mail.text_part&.body&.decoded ].compact.join("\n")

      expect(body).to include('Ce que tu nous as dit')
      expect(body).to include('anniversaire de Jules')
    end

    it "affiche le champ de commentaire sur la page de réservation" do
      get pizza_party_privee_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Parle-nous de ton groupe')
      expect(response.body).to include('name="party_note"')
      expect(response.body).to include('maxlength="500"')
    end

    it 'propose de corriger le commentaire au checkout' do
      sign_in(customer)
      add_party_to_cart

      get new_checkout_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('order_customer_note')
      expect(response.body).to include(CGI.escapeHTML(note))
    end
  end

  describe "ce qui ne doit PAS gagner de commentaire" do
    let(:customer) { create(:customer, first_name: 'Zoé', email: 'zoe@example.com', cash_payment_allowed: true) }
    let!(:bake_day) { create(:bake_day, :can_order) }
    let!(:bread_product) { create(:product, :bread, channel: 'store') }
    let!(:bread_variant) { create(:product_variant, product: bread_product, price_cents: 450, channel: 'store') }

    it "une commande de pain se passe de commentaire et n'en porte aucun" do
      sign_in(customer)
      post cart_add_path, params: { product_variant_id: bread_variant.id, bake_day_id: bake_day.id, qty: 2 }

      post '/checkout/create_cash_order',
           params: { first_name: 'Zoé', bake_day_id: bake_day.id }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      order = Order.order(:created_at).last
      expect(order.customer_note).to be_nil
    end

    it "la page de commande d'une party ANCIENNE (sans commentaire) s'affiche sans erreur" do
      legacy = PartyOrderCreationService.new(
        customer: customer,
        party_event: create(:party_event, :private_party),
        cart_items: [ { 'product_variant_id' => party_variant.id.to_s, 'qty' => '3' } ]
      ).call
      expect(legacy.customer_note).to be_nil

      get order_path(legacy.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Ce que tu nous as dit')
    end
  end
end
