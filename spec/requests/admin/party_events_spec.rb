require "rails_helper"

RSpec.describe "Admin party events (#pizza-parties)", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  describe "événements publics" do
    it "crée un événement public" do
      expect {
        post admin_party_events_path, params: {
          party_event: { title: "Pizza Party de juillet", held_on: Date.current + 10, capacity: 40, registration_closes_at: 8.days.from_now }
        }
      }.to change(PartyEvent.public_events, :count).by(1)

      expect(response).to redirect_to(admin_party_events_path)
      event = PartyEvent.last
      expect(event.kind_public_party?).to be true
      expect(event.title).to eq("Pizza Party de juillet")
    end

    it "rend le formulaire public : trix-editor, capacité/clôture requises, pas de créneau" do
      get new_admin_party_event_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("trix-editor")
      expect(response.body).to include("Capacité (personnes)")
      expect(response.body).to include("Clôture des inscriptions")
      expect(response.body).not_to include("Créneau")
    end

    it "liste les événements publics à venir" do
      create(:party_event, :public_party, title: "Grande Pizza Party", held_on: Date.current + 5)

      get admin_party_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grande Pizza Party")
    end

    it "supprime (soft) un événement" do
      event = create(:party_event, :public_party)

      delete admin_party_event_path(event)

      expect(response).to redirect_to(admin_party_events_path)
      expect(event.reload.deleted_at).to be_present
    end
  end

  describe "blocages de créneaux privés" do
    it "bloque un créneau (le rend indisponible)" do
      expect {
        post admin_party_slot_blocks_path, params: { party_slot_block: { blocked_on: Date.current + 3, slot: "soir" } }
      }.to change(PartySlotBlock, :count).by(1)

      expect(PartyEvent.private_slot_available?(Date.current + 3, "soir")).to be false
    end

    it "retire un blocage" do
      block = create(:party_slot_block, blocked_on: Date.current + 3, slot: :midi)

      delete admin_party_slot_block_path(block)

      expect(response).to redirect_to(admin_party_slot_blocks_path)
      expect(PartySlotBlock.exists?(block.id)).to be false
    end
  end

  describe "capacité par créneau (paramètres de production)" do
    it "met à jour la capacité" do
      patch admin_settings_production_setting_path, params: {
        production_setting: { oven_capacity_grams: 110_000, market_day_oven_capacity_grams: 165_000, private_party_slot_capacity: 4 }
      }

      expect(ProductionSetting.current.private_party_slot_capacity).to eq(4)
    end
  end
end
