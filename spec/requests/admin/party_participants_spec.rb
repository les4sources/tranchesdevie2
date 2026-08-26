require "rails_helper"

# #206 — la liste nominative sur la fiche de l'événement. Données INVENTÉES
# uniquement : le dépôt est public.
RSpec.describe "Admin — participants importés d'une party", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:date) { Date.new(2026, 7, 17) }
  let!(:default_pickup) { create(:pickup_location, :default) }

  let!(:event) do
    create(:party_event, :public_party, held_on: date,
                                        historical_source: "billetweb",
                                        historical_adults: 35, historical_children: 16,
                                        historical_sourciers: 13, historical_fees_cents: 2_713)
  end

  subject(:body) do
    get admin_party_event_path(event)
    response.body
  end

  context "sans liste importée" do
    it "affiche l'agrégat seul, sans bloc nominatif" do
      expect(response_status_ok(body)).to be true
      expect(body).to include("Ventes importées")
      expect(body).not_to include("Qui était là")
    end
  end

  context "avec une liste importée" do
    let!(:adults) do
      3.times.map { create(:party_participant, party_event: event, last_name: "Dupuis", first_name: Faker::Name.first_name) }
    end
    let!(:child) { create(:party_participant, :child, party_event: event, last_name: "Dupuis", first_name: "Lou") }

    it "affiche la liste nominative dans un bloc distinct de l'agrégat" do
      expect(body).to include("Ventes importées")
      expect(body).to include("Qui était là")
      expect(body).to include("Dupuis")
      expect(body).to include("4 participants · 3 adultes · 1 enfants")
    end

    it "dit explicitement que la comptabilité vient de l'agrégat" do
      expect(body).to include("Liste nominative — hors comptabilité")
      expect(body).to include("la comptabilité de cet événement vient des chiffres agrégés")
      expect(body).to include("aucune commande n'a été créée pour ces participants")
    end

    it "garde les chiffres agrégés intacts à l'écran" do
      expect(body).to include("35")
      expect(body).to include("16")
      expect(body).to include("13")
    end

    it "distingue adultes et enfants" do
      expect(body).to include("Adulte")
      expect(body).to include("Enfant")
    end
  end

  def response_status_ok(_body)
    response.status == 200
  end
end
