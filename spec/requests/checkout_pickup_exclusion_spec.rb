require "rails_helper"

# Exclusion produit ↔ lieu de retrait (#152) au checkout : feedback client
# (données + avertissement) et garde serveur sur le chemin Stripe.
RSpec.describe "Checkout — exclusion produit / lieu de retrait", type: :request do
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }

  let(:bake_day) { create(:bake_day, :can_order) }
  let!(:product) { create(:product, name: "Pain surprise", channel: "store") }
  let!(:variant) { create(:product_variant, product: product, channel: "store", price_cents: 550) }
  let(:customer) { create(:customer, first_name: "Léa") }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
    bake_day.save!
    product.excluded_pickup_locations << anhee

    post "/connexion", params: { identifier: customer.phone_e164 }
    post "/connexion", params: { identifier: customer.phone_e164, otp_code: "123456" }
    post "/cart/add", params: { product_variant_id: variant.id, bake_day_id: bake_day.id, quantity: 1 }
  end

  def post_json(path, body)
    post path, params: body.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end

  describe "écran de checkout" do
    it "expose les données d'exclusion et le bloc d'avertissement" do
      get "/checkout/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("pickup_exclusions_data")
      expect(response.body).to include("pickup_exclusion_warning")
      # Le nom du produit exclu figure dans les données JSON injectées.
      expect(response.body).to include("Pain surprise")
      # La carte du lieu exclu (anhee) et le lieu par défaut sont bien présents.
      expect(response.body).to match(/"#{anhee.id}":/)
    end
  end

  describe "garde serveur (chemin Stripe)" do
    before { stub_stripe_payment_intent_create(amount: 550) }

    it "refuse la commande pour le lieu exclu" do
      post_json "/checkout/create_payment_intent", { first_name: "Léa", pickup_location_id: anhee.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Pain surprise")
      expect(Order.count).to eq(0)
    end

    it "autorise la commande pour un lieu non exclu" do
      post_json "/checkout/create_payment_intent", { first_name: "Léa", pickup_location_id: default_location.id }

      expect(response).to have_http_status(:ok)
      expect(Order.order(:created_at).last.pickup_location).to eq(default_location)
    end
  end
end
