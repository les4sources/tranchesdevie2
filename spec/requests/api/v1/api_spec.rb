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

  # Rattachement d'une Pizza party privée à un séjour Claudy (#290) : Claudy lit
  # cette API pour proposer un sélecteur de parties, puis re-synchronise pour
  # refléter une annulation ou un remboursement.
  describe "GET /api/v1/orders — Pizza parties privées (#290)" do
    let!(:default_pickup) { create(:pickup_location, :default) }
    let(:customer) { create(:customer, first_name: "Alix", last_name: "Renard", email: "alix@example.com") }
    let(:party_product) { create(:product, :pizza_party) }
    let(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500) }
    let(:public_product) { create(:product, :pizza_party_public) }
    let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000) }

    def party_order(event:, variant: paton, qty: "6", cust: nil)
      PartyOrderCreationService.new(
        customer: cust || customer,
        party_event: event,
        cart_items: [ { "product_variant_id" => variant.id.to_s, "qty" => qty } ]
      ).call
    end

    def private_party_order(held_on: Date.new(2026, 10, 9), qty: "18", cust: nil)
      party_order(event: create(:party_event, :private_party, held_on: held_on, slot: :soir), qty: qty, cust: cust)
    end

    def fetch(query)
      get "/api/v1/orders?#{query}", headers: auth
      JSON.parse(response.body)
    end

    it "ne renvoie que les parties privées avec kind=private_party" do
      private_order = private_party_order
      party_order(event: create(:party_event, :public_party), variant: adulte)
      create(:order, :with_items, customer: customer)

      ids = fetch("kind=private_party")["data"].map { |o| o["id"] }

      expect(ids).to eq([ private_order.id ])
    end

    it "refuse un kind inconnu avec l'enveloppe d'erreur standard (400)" do
      get "/api/v1/orders?kind=anniversaire", headers: auth

      expect(response).to have_http_status(:bad_request)
      error = JSON.parse(response.body)["error"]
      expect(error["code"]).to eq("invalid_filter")
      expect(error["message"]).to include("private_party")
      expect(error["documentation_url"]).to be_present
    end

    it "borne sur la date de la party, bornes incluses" do
      octobre = private_party_order(held_on: Date.new(2026, 10, 9))
      novembre = private_party_order(held_on: Date.new(2026, 11, 6))

      expect(fetch("held_on_from=2026-10-01&held_on_to=2026-10-31")["data"].map { |o| o["id"] })
        .to eq([ octobre.id ])
      expect(fetch("held_on_from=2026-10-09&held_on_to=2026-10-09")["data"].map { |o| o["id"] })
        .to eq([ octobre.id ])
      expect(fetch("held_on_from=2026-11-01")["data"].map { |o| o["id"] })
        .to eq([ novembre.id ])
    end

    it "refuse une date invalide (400)" do
      get "/api/v1/orders?held_on_from=le-9-octobre", headers: auth

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body).dig("error", "message")).to include("YYYY-MM-DD")
    end

    it "filtre sur le paiement reçu, Stripe comme encaissement pointé" do
      stripe_paid = private_party_order
      stripe_paid.update!(payment_status: :paid)
      create(:payment, order: stripe_paid)
      cash_pointed = private_party_order(held_on: Date.new(2026, 10, 16))
      cash_pointed.update!(payment_status: :paid, offline_payment_method: :cash)
      unpaid = private_party_order(held_on: Date.new(2026, 10, 23))

      paid_ids = fetch("kind=private_party&paid=true")["data"].map { |o| o["id"] }
      unpaid_ids = fetch("kind=private_party&paid=false")["data"].map { |o| o["id"] }

      expect(paid_ids).to match_array([ stripe_paid.id, cash_pointed.id ])
      expect(unpaid_ids).to eq([ unpaid.id ])
    end

    it "refuse une valeur de paid autre que true/false (400)" do
      get "/api/v1/orders?paid=peut-etre", headers: auth

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("invalid_filter")
    end

    it "embarque le résumé de la party et du client" do
      order = private_party_order
      create(:party_request, :accepted, customer: customer, order: order,
                                        group_name: "Scouts de Namur", forfait: true)

      record = fetch("kind=private_party")["data"].first

      expect(record["party"]).to include(
        "party_event_id" => order.party_event_id,
        "kind" => "private_party",
        "held_on" => "2026-10-09",
        "slot" => "soir",
        "group_name" => "Scouts de Namur",
        "persons" => 18,
        "forfait" => true
      )
      expect(record["party"]["admin_url"]).to end_with("/admin/parties/#{order.party_event_id}")
      expect(record["customer"]).to include(
        "id" => customer.id, "full_name" => "Alix Renard", "email" => "alix@example.com"
      )
    end

    it "laisse party à null pour une commande de pain" do
      create(:order, :with_items, customer: customer)

      record = fetch("customer_id=#{customer.id}")["data"].first

      expect(record["party"]).to be_nil
      expect(record["cancelled"]).to be false
      expect(record["refunded"]).to be false
      expect(record["refunded_at"]).to be_nil
    end

    it "expose la party saisie en admin sans demande client (groupe null)" do
      order = private_party_order

      record = fetch("kind=private_party")["data"].first

      expect(record["party"]["group_name"]).to be_nil
      expect(record["party"]["forfait"]).to be false
      expect(record["party"]["persons"]).to eq(18)
    end

    it "signale un remboursement Stripe abouti" do
      order = private_party_order
      payment = create(:payment, :refunded, order: order)

      record = fetch("kind=private_party")["data"].first

      expect(record["refunded"]).to be true
      expect(record["refunded_at"]).to eq(payment.updated_at.iso8601)
    end

    it "signale un remboursement au portefeuille" do
      order = private_party_order
      wallet = create(:wallet, customer: customer)
      refund = create(:wallet_transaction, :order_refund, wallet: wallet, order: order)

      record = fetch("kind=private_party")["data"].first

      expect(record["refunded"]).to be true
      expect(record["refunded_at"]).to eq(refund.created_at.iso8601)
    end

    it "signale une party annulée" do
      order = private_party_order
      order.update!(status: :cancelled)

      record = fetch("kind=private_party")["data"].first

      expect(record["cancelled"]).to be true
    end

    it "expose les mêmes champs sur le show" do
      order = private_party_order

      get "/api/v1/orders/#{order.id}", headers: auth
      record = JSON.parse(response.body)["data"]

      expect(record["party"]["party_event_id"]).to eq(order.party_event_id)
      expect(record["customer"]["id"]).to eq(customer.id)
      expect(record).to include("cancelled", "refunded", "refunded_at")
    end

    it "ne fait pas exploser le nombre de requêtes avec cinq parties (pas de N+1)" do
      5.times { |n| private_party_order(held_on: Date.new(2026, 10, 9) + (n * 7)) }

      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name].to_s.in?([ "SCHEMA", "TRANSACTION" ]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/api/v1/orders?kind=private_party", headers: auth
      end

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"].size).to eq(5)
      # Comptage + commandes + une requête par association préchargée : une
      # dizaine, jamais proportionnel au nombre de parties.
      expect(queries).to be < 20
    end

    it "documente les nouveaux filtres dans le catalogue et l'OpenAPI" do
      get "/api/v1/openapi.json", headers: auth
      spec = response.body

      expect(spec).to include("kind")
      expect(spec).to include("held_on_from")
      expect(spec).to include("held_on_to")
      expect(spec).to include("paid")
    end
  end
end
