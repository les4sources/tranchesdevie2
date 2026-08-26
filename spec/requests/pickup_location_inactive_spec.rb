require "rails_helper"

# #199 — un point de retrait désactivé disparaît des choix du client et de nulle
# part ailleurs. Le cas réel : « Ferme de Champale » ne sert plus, mais ses
# commandes passées doivent rester lisibles.
RSpec.describe "Point de retrait désactivé", type: :request do
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:champale) { create(:pickup_location, name: "Ferme de Champale", description: "Chez Champale.") }

  let(:bake_day) { create(:bake_day, :can_order) }
  let!(:product) { create(:product, channel: "store") }
  let!(:variant) { create(:product_variant, product: product, channel: "store", price_cents: 550) }
  let(:customer) { create(:customer, first_name: "Léa") }

  before do
    bake_day.pickup_location_ids = [ default_location.id, champale.id ]
    bake_day.save!
  end

  describe "côté client — checkout" do
    before do
      allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
      allow(OtpService).to receive(:verify_code).and_return({ success: true })

      post "/connexion", params: { identifier: customer.phone_e164 }
      post "/connexion", params: { identifier: customer.phone_e164, otp_code: "123456" }
      post "/cart/add", params: { product_variant_id: variant.id, bake_day_id: bake_day.id, quantity: 1 }
    end

    it "propose le lieu tant qu'il est actif" do
      get "/checkout/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(champale.name))
    end

    it "ne le propose plus une fois désactivé" do
      champale.update!(active: false)

      get "/checkout/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(CGI.escapeHTML(champale.name))
      expect(response.body).to include(CGI.escapeHTML(default_location.name))
    end
  end

  describe "côté client — calendrier" do
    it "ne propose plus le lieu désactivé" do
      champale.update!(active: false)

      expect(bake_day.orderable_pickup_locations).to contain_exactly(default_location)
    end
  end

  describe "côté admin" do
    before do
      ENV["ADMIN_PASSWORD"] = "test-admin-pw"
      post admin_login_path, params: { password: "test-admin-pw" }
    end

    it "reste listé, marqué « Inactif », dans l'écran des points de retrait" do
      champale.update!(active: false)

      get admin_pickup_locations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(champale.name))
      expect(response.body).to include("Inactif")
    end

    it "expose la case à cocher au formulaire d'édition" do
      get edit_admin_pickup_location_path(champale)

      expect(response.body).to include("pickup_location[active]")
      expect(response.body).to include("Actif — proposé aux clients")
    end

    it "enregistre la bascule depuis le formulaire" do
      patch admin_pickup_location_path(champale), params: { pickup_location: { active: "0" } }
      expect(champale.reload.active?).to be false

      patch admin_pickup_location_path(champale), params: { pickup_location: { active: "1" } }
      expect(champale.reload.active?).to be true
    end

    it "refuse de désactiver le lieu par défaut" do
      patch admin_pickup_location_path(default_location), params: { pickup_location: { active: "0" } }

      expect(default_location.reload.active?).to be true
      expect(response.body).to include("par défaut")
    end
  end

  describe "l'historique d'une commande sur un lieu devenu inactif" do
    let!(:order) do
      create(:order, :paid, customer: customer, bake_day: bake_day,
                            pickup_location: champale, total_cents: 550).tap do |o|
        create(:order_item, order: o, product_variant: variant, qty: 1, unit_price_cents: 550)
      end
    end

    before do
      champale.update!(active: false)
      ENV["ADMIN_PASSWORD"] = "test-admin-pw"
      post admin_login_path, params: { password: "test-admin-pw" }
    end

    it "reste dans la répartition par point de retrait du jour, marquée « Lieu inactif »" do
      get admin_bake_day_path(bake_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(champale.name))
      expect(response.body).to include("Lieu inactif")
    end

    it "garde sa feuille de retrait PDF générable" do
      get pickup_sheet_admin_bake_day_path(bake_day, pickup_location_id: champale.id)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body.bytesize).to be > 0
    end

    it "s'affiche normalement sur la fiche de la commande" do
      get admin_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(champale.name))
    end
  end
end
