require "rails_helper"

# Admin des lieux de vente (#150) : CRUD, coûts historisés, liaison depuis le
# formulaire jour de cuisson, et ligne de déduction dans le rapport boulangers.
RSpec.describe "Admin — lieux de vente", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  describe "CRUD lieu de vente" do
    it "liste les lieux de vente" do
      create(:sales_location, name: "Marché d'Anhée")
      get admin_settings_sales_locations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML("Marché d'Anhée"))
    end

    it "crée un lieu de vente" do
      expect {
        post admin_settings_sales_locations_path, params: {
          sales_location: { name: "Marché de Dinant", active: "1", position: 2 }
        }
      }.to change(SalesLocation, :count).by(1)

      expect(SalesLocation.last.name).to eq("Marché de Dinant")
    end

    it "met à jour un lieu de vente" do
      location = create(:sales_location, name: "Anhée")
      patch admin_settings_sales_location_path(location), params: {
        sales_location: { name: "Marché d'Anhée", active: "1" }
      }

      expect(location.reload.name).to eq("Marché d'Anhée")
    end

    it "supprime un lieu en soft delete" do
      location = create(:sales_location)
      delete admin_settings_sales_location_path(location)

      expect(location.reload.deleted_at).to be_present
      expect(SalesLocation.not_deleted).not_to include(location)
    end
  end

  describe "coûts historisés" do
    let(:location) { create(:sales_location, name: "Marché d'Anhée") }

    it "ajoute un palier de coût saisi en euros" do
      expect {
        post admin_settings_sales_location_sales_location_costs_path(location), params: {
          sales_location_cost: { amount_euros: "25,50", valid_from: "2026-01-01", valid_until: "" }
        }
      }.to change(SalesLocationCost, :count).by(1)

      cost = SalesLocationCost.last
      expect(cost.amount_cents).to eq(2_550)
      expect(cost.valid_until).to be_nil
    end

    it "refuse une période dont la fin précède le début" do
      expect {
        post admin_settings_sales_location_sales_location_costs_path(location), params: {
          sales_location_cost: { amount_euros: "25", valid_from: "2026-03-01", valid_until: "2026-02-01" }
        }
      }.not_to change(SalesLocationCost, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "liaison au jour de cuisson" do
    it "permet de cocher des lieux de vente à la création d'une fournée" do
      create(:pickup_location, :default)
      location = create(:sales_location, name: "Marché d'Anhée")

      post admin_bake_days_path, params: {
        bake_day: {
          baked_on: Date.current.next_occurring(:tuesday).to_s,
          cut_off_at: 2.days.from_now.to_s,
          sales_location_ids: [ location.id ]
        }
      }

      expect(BakeDay.last.sales_locations).to include(location)
    end

    it "affiche le sélecteur de lieux de vente dans le formulaire" do
      create(:sales_location, name: "Marché d'Anhée")
      get new_admin_bake_day_path

      expect(response.body).to include("Lieux de vente")
      expect(response.body).to include(CGI.escapeHTML("Marché d'Anhée"))
    end
  end

  describe "rapport boulangers" do
    it "affiche une ligne de déduction pour les lieux de vente" do
      get baker_revenue_admin_reports_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lieux de vente")
    end
  end
end
