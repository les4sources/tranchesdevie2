require 'rails_helper'

# Filtre client de la page Commandes (retour de Stéphanie : impossible de
# retrouver une commande par son client). On couvre les trois façons naturelles
# de désigner quelqu'un — nom, e-mail, téléphone — plus le verrouillage sur un
# client précis via l'autocomplétion.
RSpec.describe "Admin::Orders — filtre client", type: :request do
  let!(:stephanie) do
    create(:customer, first_name: "Stéphanie", last_name: "Dubois",
                      email: "stephanie.dubois@example.com", phone_e164: "+32472112233")
  end
  let!(:other) do
    create(:customer, first_name: "Marc", last_name: "Lambert",
                      email: "marc.lambert@example.com", phone_e164: "+32499887766")
  end

  # Une seule fournée : `baked_on` est unique, deux bake_days implicites se
  # marcheraient dessus.
  let!(:bake_day) { create(:bake_day) }
  let!(:her_order) { create(:order, :paid, :with_items, customer: stephanie, bake_day: bake_day) }
  let!(:his_order) { create(:order, :paid, :with_items, customer: other, bake_day: bake_day) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ADMIN_PASSWORD').and_return('secret')
    post admin_login_path, params: { password: 'secret' }
  end

  describe "GET /admin/orders" do
    it "lists every order when no filter is applied" do
      get admin_orders_path

      expect(response.body).to include(her_order.order_number)
      expect(response.body).to include(his_order.order_number)
    end

    it "filters by customer name" do
      get admin_orders_path, params: { q: "dubois" }

      expect(response.body).to include(her_order.order_number)
      expect(response.body).not_to include(his_order.order_number)
    end

    it "filters by a fragment of the e-mail address" do
      get admin_orders_path, params: { q: "stephanie.dub" }

      expect(response.body).to include(her_order.order_number)
      expect(response.body).not_to include(his_order.order_number)
    end

    it "filters by phone number typed in national form" do
      get admin_orders_path, params: { q: "0472 11 22 33" }

      expect(response.body).to include(her_order.order_number)
      expect(response.body).not_to include(his_order.order_number)
    end

    it "filters by a leading phone prefix typed with the national zero" do
      get admin_orders_path, params: { q: "047" }

      expect(response.body).to include(her_order.order_number)
      expect(response.body).not_to include(his_order.order_number)
    end

    it "filters by the order number itself" do
      get admin_orders_path, params: { q: her_order.order_number }

      expect(response.body).to include(her_order.order_number)
      expect(response.body).not_to include(his_order.order_number)
    end

    it "locks onto a single customer when customer_id is supplied" do
      get admin_orders_path, params: { customer_id: stephanie.id }

      expect(response.body).to include(her_order.order_number)
      expect(response.body).not_to include(his_order.order_number)
      expect(response.body).to include("stephanie.dubois@example.com")
    end

    it "shows an empty state when nothing matches" do
      get admin_orders_path, params: { q: "personne-de-ce-nom" }

      expect(response.body).to include("Aucune commande ne correspond")
      expect(response.body).not_to include(her_order.order_number)
    end

    it "combines the customer filter with the status filter" do
      ready_order = create(:order, :ready, :with_items, customer: stephanie, bake_day: bake_day)

      get admin_orders_path, params: { customer_id: stephanie.id, status: "ready" }

      expect(response.body).to include(ready_order.order_number)
      expect(response.body).not_to include(her_order.order_number)
    end
  end

  describe "GET /admin/customers/search" do
    it "returns matching customers as JSON with contact details" do
      get search_admin_customers_path, params: { q: "dubois" }

      payload = JSON.parse(response.body)
      expect(payload["query"]).to eq("dubois")
      expect(payload["results"].size).to eq(1)
      expect(payload["results"].first).to include(
        "id" => stephanie.id,
        "name" => "Stéphanie Dubois",
        "email" => "stephanie.dubois@example.com",
        "phone" => "+32472112233",
        "orders_count" => 1
      )
    end

    it "finds a customer by the last digits of their phone number" do
      get search_admin_customers_path, params: { q: "112233" }

      names = JSON.parse(response.body)["results"].map { |c| c["name"] }
      expect(names).to eq([ "Stéphanie Dubois" ])
    end

    it "returns nothing for a blank query" do
      get search_admin_customers_path, params: { q: "" }

      expect(JSON.parse(response.body)["results"]).to be_empty
    end

    it "requires an authenticated admin" do
      delete admin_logout_path
      get search_admin_customers_path, params: { q: "dubois" }

      expect(response).to redirect_to(admin_login_path)
    end
  end
end
