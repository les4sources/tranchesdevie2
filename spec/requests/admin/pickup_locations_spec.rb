require "rails_helper"

# Admin des points de retrait (#148) : CRUD, cochage bidirectionnel lieu ↔ fournée,
# onglet « Par point de retrait » du tableau de bord et feuille de retrait PDF.
RSpec.describe "Admin — points de retrait", type: :request do
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée", description: "Sur notre étal.") }

  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  describe "CRUD" do
    it "liste les points de retrait" do
      get admin_pickup_locations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Les 4 Sources")
      expect(response.body).to include(CGI.escapeHTML("Marché d'Anhée"))
    end

    it "crée un point de retrait" do
      expect {
        post admin_pickup_locations_path, params: {
          pickup_location: { name: "Marché de Dinant", description: "Place Reine Astrid.", position: 3 }
        }
      }.to change(PickupLocation, :count).by(1)

      expect(PickupLocation.last.name).to eq("Marché de Dinant")
    end

    it "supprime un lieu en soft delete, sans casser les commandes qui le référencent" do
      bake_day = create(:bake_day, :can_order)
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!
      order = create(:order, bake_day: bake_day, pickup_location: anhee)

      delete admin_pickup_location_path(anhee)

      expect(anhee.reload.deleted_at).to be_present
      expect(PickupLocation.not_deleted).not_to include(anhee)
      expect(order.reload.pickup_location).to eq(anhee) # toujours lisible
    end

    it "refuse de supprimer le lieu par défaut" do
      delete admin_pickup_location_path(default_location)

      expect(default_location.reload.deleted_at).to be_nil
    end
  end

  describe "cochage des fournées depuis la fiche du lieu" do
    let(:bake_day) { create(:bake_day, :can_order) }

    it "ouvre le lieu sur les fournées cochées" do
      patch admin_pickup_location_path(anhee), params: {
        pickup_location: { name: anhee.name, bake_day_ids: [ bake_day.id ] }
      }

      expect(bake_day.reload.open_pickup_locations).to include(anhee)
    end
  end

  describe "cochage des lieux depuis la fiche de la fournée" do
    let(:bake_day) { create(:bake_day, :can_order) }

    it "ouvre les lieux cochés" do
      patch admin_bake_day_path(bake_day), params: {
        bake_day: { baked_on: bake_day.baked_on, cut_off_at: bake_day.cut_off_at,
                    pickup_location_ids: [ default_location.id, anhee.id ] }
      }

      expect(bake_day.reload.open_pickup_locations).to contain_exactly(default_location, anhee)
    end

    it "REFUSE de décocher un lieu utilisé par des commandes de cette fournée" do
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!
      create(:order, bake_day: bake_day, pickup_location: anhee)
      create(:order, bake_day: bake_day, pickup_location: anhee)

      patch admin_bake_day_path(bake_day), params: {
        bake_day: { baked_on: bake_day.baked_on, cut_off_at: bake_day.cut_off_at,
                    pickup_location_ids: [ default_location.id ] }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("2 commandes")
      # Le lieu est toujours ouvert : rien n'a été supprimé.
      expect(bake_day.reload.open_pickup_locations).to include(anhee)
    end
  end

  describe "tableau de bord de fournée" do
    let(:bake_day) { create(:bake_day, :can_order) }
    let(:product) { create(:product, :bread, name: "Pain froment") }
    let(:variant) { create(:product_variant, product: product, name: "Grand 1 kg", price_cents: 700) }

    before do
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!

      order = create(:order, :paid, bake_day: bake_day, pickup_location: anhee, total_cents: 1400)
      create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 700)
    end

    it "affiche l'onglet « Par point de retrait » avec le récapitulatif du lieu" do
      get admin_bake_day_path(bake_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Par point de retrait")
      expect(response.body).to include("Articles à préparer pour ce lieu")
      expect(response.body).to include(CGI.escapeHTML("Marché d'Anhée"))
    end

    it "propose le téléchargement de la feuille de retrait PDF" do
      get pickup_sheet_admin_bake_day_path(bake_day, pickup_location_id: anhee.id)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end
end
