require "rails_helper"

# Ressource « points de retrait » exposée à l'API agent (#148).
RSpec.describe "Api::V1 pickup_locations", type: :request do
  let(:api_key) { "test-secret-key" }
  let(:auth) { { "Authorization" => "Bearer #{api_key}" } }

  around do |example|
    original = ENV["TRANCHESDEVIE_API_KEY"]
    ENV["TRANCHESDEVIE_API_KEY"] = api_key
    example.run
    ENV["TRANCHESDEVIE_API_KEY"] = original
  end

  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée", description: "Sur notre étal.") }

  it "exige un token" do
    get "/api/v1/pickup_locations"

    expect(response).to have_http_status(:unauthorized)
  end

  it "liste les points de retrait non supprimés" do
    deleted = create(:pickup_location, name: "Ancien marché", deleted_at: Time.current)

    get "/api/v1/pickup_locations", headers: auth

    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body)["data"].map { |l| l["name"] }
    expect(names).to contain_exactly("Les 4 Sources", "Marché d'Anhée")
    expect(names).not_to include(deleted.name)
  end

  it "expose le drapeau « par défaut »" do
    get "/api/v1/pickup_locations/#{default_location.id}", headers: auth

    data = JSON.parse(response.body)["data"]
    expect(data["name"]).to eq("Les 4 Sources")
    expect(data["default"]).to be true
    expect(data["deleted"]).to be false
  end

  it "laisse consultable un lieu supprimé (des commandes le référencent encore)" do
    anhee.soft_delete!

    get "/api/v1/pickup_locations/#{anhee.id}", headers: auth

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("data", "deleted")).to be true
  end

  describe "champ point de retrait sur une commande" do
    it "expose le lieu de retrait de la commande" do
      bake_day = create(:bake_day, :can_order)
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!
      order = create(:order, bake_day: bake_day, pickup_location: anhee)

      get "/api/v1/orders/#{order.id}", headers: auth

      data = JSON.parse(response.body)["data"]
      expect(data["pickup_location_id"]).to eq(anhee.id)
      expect(data.dig("pickup_location", "name")).to eq("Marché d'Anhée")
      expect(data.dig("_links", "pickup_location")).to include("pickup_locations")
    end
  end

  describe "découvrabilité" do
    it "apparaît dans l'index de découverte" do
      get "/api/v1", headers: auth

      expect(response.body).to include("pickup_locations")
    end

    # Les 3 surfaces de doc sont générées depuis ResourceCatalog : les y voir
    # toutes prouve que le catalogue est bien la source de vérité.
    it "apparaît dans le spec OpenAPI (chemins relatifs au basePath)" do
      get "/api/v1/openapi", headers: auth

      paths = JSON.parse(response.body)["paths"]
      expect(paths).to have_key("/pickup_locations")
      expect(paths).to have_key("/pickup_locations/{id}")
    end

    it "apparaît dans le guide markdown" do
      get "/api/v1/docs", headers: auth

      expect(response.body).to include("pickup_locations")
    end
  end
end
