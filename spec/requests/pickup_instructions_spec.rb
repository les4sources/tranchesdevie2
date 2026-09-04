require "rails_helper"

# Les instructions de retrait (#252) suivent la commande sur les trois surfaces
# vues par le client : la confirmation, l'e-mail de confirmation, et la page
# commande. Règle commune : vides, elles n'affichent NI bloc NI libellé orphelin.
RSpec.describe "Instructions de retrait", type: :request do
  let(:instructions) { "Le jour de la cuisson, à partir de 18h." }
  let!(:default_location) { create(:pickup_location, :default, pickup_instructions: instructions) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée", description: "Sur notre étal.") }

  let(:bake_day) { create(:bake_day, :can_order) }
  let(:customer) { create(:customer, first_name: "Léa", email: "lea@example.com") }

  # Les deux lieux doivent être ouverts sur la fournée, sinon la commande est
  # refusée par la validation de disponibilité.
  before do
    bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
    bake_day.save!
  end

  let(:order) { create(:order, :with_items, customer: customer, bake_day: bake_day, pickup_location: default_location) }
  let(:order_without_instructions) { create(:order, :with_items, customer: customer, bake_day: bake_day, pickup_location: anhee) }

  describe "l'écran de confirmation" do
    it "affiche le nom du lieu et ses instructions" do
      get "/checkout/success", params: { order_token: order.public_token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(default_location.name))
      expect(response.body).to include(CGI.escapeHTML(instructions))
    end

    it "n'affiche ni bloc ni libellé quand les instructions sont vides" do
      get "/checkout/success", params: { order_token: order_without_instructions.public_token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(anhee.name))
      expect(response.body).not_to include(CGI.escapeHTML(instructions))
    end
  end

  describe "la page commande du client" do
    it "affiche les instructions sous la description" do
      get order_path(order.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(default_location.name))
      expect(response.body).to include(CGI.escapeHTML(instructions))
    end

    it "n'affiche rien de plus quand les instructions sont vides" do
      get order_path(order_without_instructions.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(anhee.name))
      expect(response.body).to include("Sur notre étal.")
      expect(response.body).not_to include(CGI.escapeHTML(instructions))
    end
  end

  describe "l'admin" do
    before do
      ENV["ADMIN_PASSWORD"] = "test-admin-pw"
      post admin_login_path, params: { password: "test-admin-pw" }
    end

    it "rend le champ sur l'écran d'édition" do
      get edit_admin_pickup_location_path(anhee)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("pickup_location[pickup_instructions]")
      expect(response.body).to include("Quand venir chercher sa commande")
    end

    it "persiste la valeur soumise" do
      patch admin_pickup_location_path(anhee), params: {
        pickup_location: { pickup_instructions: "Le samedi, de 9h à 13h." }
      }

      expect(anhee.reload.pickup_instructions).to eq("Le samedi, de 9h à 13h.")
    end

    it "laisse le champ vide quand rien n'est saisi" do
      patch admin_pickup_location_path(anhee), params: {
        pickup_location: { pickup_instructions: "" }
      }

      expect(anhee.reload.pickup_instructions).to be_blank
    end
  end
end
