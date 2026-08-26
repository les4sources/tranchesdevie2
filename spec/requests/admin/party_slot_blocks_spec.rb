require "rails_helper"

# #200 — `/admin/parties/blocages` renvoyait une 404 : `resources :party_events,
# path: "parties"` était déclaré en premier et capturait l'URL comme
# `party_events#show` avec `id: "blocages"`.
#
# Ces specs verrouillent l'ordre des routes. Elles échouent si on le réinverse.
RSpec.describe "Admin::PartySlotBlocks — routage", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  # C'est ICI que se joue la non-régression : si l'ordre des routes est
  # réinversé, `/admin/parties/blocages` se reconnaît de nouveau comme
  # `party_events#show` avec `id: "blocages"` et ces deux exemples tombent.
  describe "l'ordre des routes" do
    def recognize(path, method)
      Rails.application.routes.recognize_path(path, method: method)
    end

    it "reconnaît GET /admin/parties/blocages comme party_slot_blocks#index, pas comme party_events#show" do
      route = recognize("/admin/parties/blocages", :get)

      expect(route[:controller]).to eq("admin/party_slot_blocks")
      expect(route[:action]).to eq("index")
      expect(route).not_to have_key(:id)
    end

    it "reconnaît DELETE /admin/parties/blocages/:id comme party_slot_blocks#destroy" do
      route = recognize("/admin/parties/blocages/42", :delete)

      expect(route[:controller]).to eq("admin/party_slot_blocks")
      expect(route[:action]).to eq("destroy")
      expect(route[:id]).to eq("42")
    end
  end

  describe "GET /admin/parties/blocages" do
    it "répond 200 et affiche l'écran de blocage des créneaux" do
      get admin_party_slot_blocks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("blocked_on")
    end
  end

  describe "POST /admin/parties/blocages" do
    it "crée un blocage de créneau" do
      expect {
        post admin_party_slot_blocks_path, params: {
          party_slot_block: { blocked_on: Date.current + 7, slot: "soir", reason: "Fermeture" }
        }
      }.to change(PartySlotBlock, :count).by(1)

      expect(response).to redirect_to(admin_party_slot_blocks_path)
      block = PartySlotBlock.last
      expect(block.blocked_on).to eq(Date.current + 7)
      expect(block.slot).to eq("soir")
    end

    it "ré-affiche l'écran quand le blocage est invalide" do
      post admin_party_slot_blocks_path, params: { party_slot_block: { blocked_on: "", slot: "soir" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /admin/parties/blocages/:id" do
    it "supprime le blocage" do
      block = PartySlotBlock.create!(blocked_on: Date.current + 7, slot: "midi")

      expect {
        delete admin_party_slot_block_path(block)
      }.to change(PartySlotBlock, :count).by(-1)

      expect(response).to redirect_to(admin_party_slot_blocks_path)
    end
  end

  # Non-régression de l'autre côté : la correction ne doit rien casser des
  # routes de `party_events`, qui partagent le segment `/admin/parties`.
  describe "les routes party_events restent intactes" do
    let!(:event) { create(:party_event, :public_party, held_on: Date.current + 14) }

    it "GET /admin/parties (index)" do
      get admin_party_events_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /admin/parties/new" do
      get new_admin_party_event_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /admin/parties/:id sur un événement existant" do
      get admin_party_event_path(event)
      expect(response).to have_http_status(:ok)
    end

    it "GET /admin/parties/:id/edit" do
      get edit_admin_party_event_path(event)
      expect(response).to have_http_status(:ok)
    end

    it "GET /admin/parties/:id sur un identifiant inexistant répond 404, comme avant" do
      get admin_party_event_path(id: 999_999)

      expect(response).to have_http_status(:not_found)
    end

    it "DELETE /admin/parties/:id (suppression douce, comme avant)" do
      delete admin_party_event_path(event)

      expect(response).to redirect_to(admin_party_events_path)
      expect(event.reload.deleted_at).to be_present
    end
  end
end
