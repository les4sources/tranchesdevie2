require "rails_helper"

# #203 — l'ajout à la main depuis la fiche d'une party publique.
RSpec.describe "Admin::PartyRegistrations", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:date) { Date.new(2026, 9, 4) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let(:product) { create(:product, :pizza_party_public, name: "Pizza party publique") }
  let!(:adulte) { create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300) }
  let!(:enfant) { create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200) }

  let!(:event) { create(:party_event, :public_party, held_on: date, capacity: 30, title: "Party de septembre") }

  def create_registration(adults: 2, children: 1, paid: "1", name: "Fabienne Renard")
    post admin_party_event_party_registrations_path(event), params: {
      registration: { name: name, adults: adults, children: children, paid: paid }
    }
  end

  describe "le bouton d'ajout" do
    it "apparaît sur la fiche d'une party publique" do
      get admin_party_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ajouter une inscription")
    end

    it "n'apparaît pas sur un événement historique importé" do
      historical = create(:party_event, :public_party, held_on: date, historical_source: "BilletWeb",
                                        historical_adults: 20, historical_children: 5,
                                        historical_fees_cents: 0, historical_sourciers: 0)

      get admin_party_event_path(historical)

      expect(response.body).not_to include("Ajouter une inscription")
    end
  end

  describe "POST create" do
    it "ajoute l'inscription et fait monter les totaux de l'événement" do
      expect { create_registration }.to change { event.reload.seats_taken }.by(3)

      order = Order.last
      expect(response).to redirect_to(admin_party_event_path(event))
      expect(order.manually_added?).to be true
      expect(order.paid?).to be true
      expect(order.total_cents).to eq(2_600)
    end

    it "ré-affiche le formulaire avec les erreurs quand il manque le nom" do
      create_registration(name: "")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Correction requise")
    end
  end

  describe "la liste des inscriptions" do
    before { create_registration }

    subject(:body) do
      get admin_party_event_path(event)
      response.body
    end

    it "distingue l'inscription manuelle de celles faites en ligne" do
      expect(body).to include("Manuelle")
      expect(body).to include("Fabienne Renard")
    end

    it "inclut l'inscription manuelle dans les totaux adultes / enfants" do
      # 2 adultes + 1 enfant, et le total en euros.
      expect(body).to include("26,00")
    end

    it "propose de modifier, basculer le paiement et supprimer" do
      order = Order.last

      expect(body).to include(edit_admin_party_event_party_registration_path(event, order))
      expect(body).to include(toggle_paid_admin_party_event_party_registration_path(event, order))
      expect(body).to include("Marquer non payée")
    end
  end

  describe "PATCH toggle_paid" do
    it "bascule dans les deux sens" do
      create_registration(paid: "0")
      order = Order.last
      expect(order.paid?).to be false

      patch toggle_paid_admin_party_event_party_registration_path(event, order)
      expect(order.reload.paid?).to be true

      patch toggle_paid_admin_party_event_party_registration_path(event, order)
      expect(order.reload.paid?).to be false
    end

    it "refuse de toucher une inscription faite en ligne" do
      customer = create(:customer)
      web = PublicPartyRegistrationService.new(
        customer: customer, party_event: event,
        cart_items: [ { "product_variant_id" => adulte.id.to_s, "qty" => "1" } ],
        payment_method: "cash"
      ).call

      patch toggle_paid_admin_party_event_party_registration_path(event, web)

      expect(response).to have_http_status(:not_found)
      expect(web.reload.paid?).to be false
    end
  end

  describe "PATCH update" do
    it "modifie les effectifs" do
      create_registration(adults: 2, children: 1)
      order = Order.last

      patch admin_party_event_party_registration_path(event, order), params: {
        registration: { name: "Fabienne Renard", adults: 4, children: 0, paid: "1" }
      }

      expect(response).to redirect_to(admin_party_event_path(event))
      expect(order.reload.total_cents).to eq(4_000)
      expect(event.reload.seats_taken).to eq(4)
    end
  end

  describe "DELETE destroy" do
    it "supprime l'inscription et libère les places" do
      create_registration
      order = Order.last

      expect { delete admin_party_event_party_registration_path(event, order) }
        .to change { event.reload.seats_taken }.by(-3)

      expect(Order.exists?(order.id)).to be false
    end
  end

  describe "non-régression historique" do
    it "un événement importé en agrégé garde exactement ses chiffres" do
      historical = create(:party_event, :public_party, held_on: date, historical_source: "BilletWeb",
                                        historical_adults: 20, historical_children: 5,
                                        historical_fees_cents: 12_345, historical_sourciers: 2)

      get admin_party_event_path(historical)

      expect(response).to have_http_status(:ok)
      expect(historical.reload.historical_adults).to eq(20)
      expect(historical.historical_children).to eq(5)
      expect(historical.historical_fees_cents).to eq(12_345)
      expect(historical.orders).to be_empty
    end
  end
end
