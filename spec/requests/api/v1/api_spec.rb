require "rails_helper"

RSpec.describe "Api::V1", type: :request do
  let(:api_key) { "test-secret-key" }
  let(:auth) { { "Authorization" => "Bearer #{api_key}" } }

  around do |example|
    original = ENV["TRANCHESDEVIE_API_KEY"]
    ENV["TRANCHESDEVIE_API_KEY"] = api_key
    example.run
    ENV["TRANCHESDEVIE_API_KEY"] = original
  end

  describe "authentication" do
    it "rejects requests without a token (401)" do
      get "/api/v1/products"
      expect(response).to have_http_status(:unauthorized)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("unauthorized")
      expect(body.dig("error", "documentation_url")).to be_present
    end

    it "rejects an invalid token (401)" do
      get "/api/v1/products", headers: { "Authorization" => "Bearer wrong-key" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 503 when the API key is not configured server-side" do
      ENV["TRANCHESDEVIE_API_KEY"] = ""
      get "/api/v1/products", headers: auth
      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("api_key_not_configured")
    end

    it "accepts a valid token" do
      get "/api/v1/products", headers: auth
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1 (discovery)" do
    it "lists resources, auth instructions and documentation links" do
      get "/api/v1", headers: auth
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("data", "authentication", "header")).to include("Bearer")
      names = body.dig("data", "resources").map { |r| r["name"] }
      expect(names).to include("products", "orders", "customers", "bake_days")
      expect(body.dig("_links", "openapi")).to be_present
      expect(body.dig("_links", "documentation")).to be_present
    end
  end

  describe "GET /api/v1/openapi" do
    it "returns a valid OpenAPI 3.1 document with bearer security and resource paths" do
      get "/api/v1/openapi", headers: auth
      body = JSON.parse(response.body)
      expect(body["openapi"]).to eq("3.1.0")
      expect(body.dig("components", "securitySchemes", "bearerAuth", "scheme")).to eq("bearer")
      expect(body["paths"].keys).to include("/products", "/products/{id}", "/orders", "/customers")
    end
  end

  describe "GET /api/v1/docs" do
    it "returns an agent-readable markdown guide" do
      get "/api/v1/docs", headers: auth
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include("Authorization: Bearer")
    end
  end

  describe "GET /api/v1/products" do
    let!(:product) { create(:product) }
    let!(:variant) { create(:product_variant, product: product) }

    it "returns a paginated collection with the standard envelope" do
      get "/api/v1/products", headers: auth
      body = JSON.parse(response.body)
      expect(body["data"]).to be_an(Array)
      expect(body["meta"]).to include("page", "per_page", "total_count", "total_pages")
      first = body["data"].first
      expect(first).to include("name", "category")
      expect(first["category"]).to eq("breads")
      expect(first.dig("_links", "self")).to eq("/api/v1/products/#{product.id}")
    end

    it "returns a single product with nested variants on show" do
      get "/api/v1/products/#{product.id}", headers: auth
      body = JSON.parse(response.body)
      expect(body.dig("data", "id")).to eq(product.id)
      expect(body.dig("data", "variants")).to be_an(Array)
      expect(body.dig("data", "variants").first["price_euros"]).to eq(5.5)
    end
  end

  describe "GET /api/v1/orders" do
    let!(:order) { create(:order, :with_items) }

    it "exposes money in cents and euros and the status as a string" do
      get "/api/v1/orders", headers: auth
      record = JSON.parse(response.body)["data"].first
      expect(record["status"]).to eq("paid")
      expect(record["total_cents"]).to be_a(Integer)
      expect(record["total_euros"]).to be_a(Numeric)
      expect(record["items"]).to be_an(Array)
      # public_token is an unauthenticated order-lookup credential — must never be exposed.
      expect(record).not_to have_key("public_token")
    end

    it "filters by status" do
      create(:order, :cancelled, bake_day: order.bake_day)
      get "/api/v1/orders?status=cancelled", headers: auth
      statuses = JSON.parse(response.body)["data"].map { |o| o["status"] }.uniq
      expect(statuses).to eq([ "cancelled" ])
    end
  end

  describe "unknown endpoint" do
    it "returns a JSON 404 envelope" do
      get "/api/v1/nonexistent", headers: auth
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("not_found")
    end
  end
end
