require 'rails_helper'

# Le point de retrait (#148) circule de bout en bout sur les TROIS chemins de
# paiement : Stripe, espèces, portefeuille.
RSpec.describe 'Checkout — point de retrait', type: :request do
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée", description: "Sur notre étal.") }
  let!(:dinant) { create(:pickup_location, name: "Marché de Dinant") }

  let(:bake_day) { create(:bake_day, :can_order) }
  let!(:product) { create(:product, channel: 'store') }
  let!(:variant) { create(:product_variant, product: product, channel: 'store', price_cents: 550) }
  let(:customer) { create(:customer, first_name: 'Léa') }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    # « Marché d'Anhée » est ouvert sur cette fournée ; « Marché de Dinant » non.
    bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
    bake_day.save!

    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
    post '/cart/add', params: { product_variant_id: variant.id, bake_day_id: bake_day.id, quantity: 1 }
  end

  def post_json(path, body)
    post path, params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
  end

  describe "l'écran de checkout" do
    it "n'affiche que les lieux ouverts sur la fournée choisie" do
      get '/checkout/new'

      # Les apostrophes sont échappées par ERB (« d&#39;Anhée ») : on compare donc
      # à la version échappée du nom.
      expect(response.body).to include(CGI.escapeHTML(anhee.name))
      expect(response.body).to include("Sur notre étal.")       # description affichée
      expect(response.body).to include("Les 4 Sources")
      expect(response.body).not_to include("Marché de Dinant")  # non ouvert sur cette fournée
    end

    it 'pré-sélectionne le lieu par défaut' do
      get '/checkout/new'

      expect(response.body).to match(/value="#{default_location.id}"[^>]*checked/)
    end
  end

  describe 'chemin Stripe (create_payment_intent)' do
    before { stub_stripe_payment_intent_create(amount: 550) }

    it 'persiste le point de retrait choisi' do
      post_json '/checkout/create_payment_intent', { first_name: 'Léa', pickup_location_id: anhee.id }

      expect(response).to have_http_status(:ok)
      expect(Order.order(:created_at).last.pickup_location).to eq(anhee)
    end

    it 'rejette un lieu non ouvert sur la fournée' do
      post_json '/checkout/create_payment_intent', { first_name: 'Léa', pickup_location_id: dinant.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Order.count).to eq(0)
    end

    it 'rejette un lieu inconnu' do
      post_json '/checkout/create_payment_intent', { first_name: 'Léa', pickup_location_id: 999_999 }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Order.count).to eq(0)
    end

    it 'retombe sur le lieu par défaut si aucun lieu n\'est transmis' do
      post_json '/checkout/create_payment_intent', { first_name: 'Léa' }

      expect(Order.order(:created_at).last.pickup_location).to eq(default_location)
    end
  end

  describe 'chemin espèces (create_cash_order)' do
    before { customer.update!(cash_payment_allowed: true) }

    it 'persiste le point de retrait choisi' do
      post_json '/checkout/create_cash_order', { first_name: 'Léa', pickup_location_id: anhee.id }

      expect(response).to have_http_status(:ok)
      expect(Order.order(:created_at).last.pickup_location).to eq(anhee)
    end

    it 'rejette un lieu non ouvert sur la fournée' do
      post_json '/checkout/create_cash_order', { first_name: 'Léa', pickup_location_id: dinant.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Order.count).to eq(0)
    end
  end

  describe 'chemin portefeuille (create_wallet_order)' do
    before { create(:wallet, customer: customer, balance_cents: 10_000) }

    it 'persiste le point de retrait choisi' do
      post_json '/checkout/create_wallet_order', { first_name: 'Léa', pickup_location_id: anhee.id }

      expect(response).to have_http_status(:ok)
      expect(Order.order(:created_at).last.pickup_location).to eq(anhee)
    end

    it 'rejette un lieu non ouvert sur la fournée' do
      post_json '/checkout/create_wallet_order', { first_name: 'Léa', pickup_location_id: dinant.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Order.count).to eq(0)
    end
  end
end
