require 'rails_helper'

# Le statut `awaiting_payment` doit être LISIBLE partout (#pizza-parties).
#
# Un écran qui affiche `awaiting_payment` en brut, ou un filtre qui ignore la
# seule commande demandant une action au client, ne sont pas des détails : c'est
# là que le client va chercher quoi faire.
RSpec.describe "Le statut « à régler » dans les écrans", type: :request do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  let(:customer) { create(:customer, first_name: "Camille", phone_e164: "+32470131313", email: "surfaces@example.com") }
  let(:party_request) { create(:party_request, customer: customer) }
  let!(:order) { PartyDecisionService.new(party_request, decided_by: "Romane").accept }

  describe "libellés" do
    include ApplicationHelper

    it "traduit le statut au lieu d'afficher la valeur brute" do
      expect(order_status_label("awaiting_payment")).to eq("À régler")
    end

    it "n'est jamais rendu en brut dans les vues" do
      expect(`rg -l 'awaiting_payment' app/views/ 2>/dev/null`.split("\n")).to all(satisfy { |file|
        File.read(file).exclude?(">awaiting_payment<")
      })
    end
  end

  describe "mon compte" do
    before do
      allow(OtpService).to receive(:send_otp).and_return({ success: true })
      allow(OtpService).to receive(:verify_otp).and_return({ success: true })
      post customer_login_path, params: { identifier: customer.phone_e164 }
      post customer_login_path, params: { identifier: customer.phone_e164, otp_code: "123456" }
    end

    it "montre la réservation à régler avec son libellé et un lien pour payer" do
      get customers_account_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("À régler")
      expect(response.body).to include(party_payment_path(token: order.public_token))
    end
  end

  describe "API agent" do
    let(:api_key) { "cle-de-test" }

    before { allow(ENV).to receive(:[]).and_call_original }

    def api_get(path)
      allow(ENV).to receive(:[]).with("TRANCHESDEVIE_API_KEY").and_return(api_key)
      get path, headers: { "Authorization" => "Bearer #{api_key}" }
    end

    it "annonce la ressource party_requests dès la page d'entrée" do
      api_get "/api/v1"

      expect(response.body).to include("party_requests")
    end

    it "décrit le statut awaiting_payment dans le guide et l'OpenAPI" do
      api_get "/api/v1/docs"
      expect(response.body).to include("awaiting_payment")
      expect(response.body).to include("Demandes de Pizza party")

      api_get "/api/v1/openapi.json"
      expect(response.body).to include("awaiting_payment")
      expect(response.body).to include("party_requests")
    end

    it "expose les demandes de party, filtrables par état" do
      api_get "/api/v1/party_requests?state=accepted"

      json = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |r| r["id"] }).to include(party_request.id)
      expect(json["data"].first["state"]).to eq("accepted")
      expect(json["data"].first["order_id"]).to eq(order.id)
    end

    it "expose une demande à l'unité avec son récit complet" do
      api_get "/api/v1/party_requests/#{party_request.id}"

      json = JSON.parse(response.body)["data"]
      expect(json["decided_by"]).to eq("Romane")
      expect(json["customer_note"]).to be_present
      expect(json["cut_off_at"]).to be_present
    end
  end
end
