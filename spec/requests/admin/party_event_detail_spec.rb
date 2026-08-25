require "rails_helper"

# Fiches de détail d'un événement party et réordonnancement de l'index (#173).
RSpec.describe "Admin — détail d'une party", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def sign_in_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:default_pickup) { create(:pickup_location, :default) }

  let(:customer) do
    create(:customer, first_name: "Alix", last_name: "Renard",
                      email: "alix@example.com", phone_e164: "+32470111222")
  end

  # --- Party privée -------------------------------------------------------
  let(:party_product) { create(:product, :pizza_party, category: :dough_balls) }
  let(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500) }
  let(:forfait_product) { create(:product, :pizza_party_forfait) }
  let(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000) }

  def private_party(held_on: Date.new(2026, 9, 4), slot: :soir, qty: 11, status: :paid, cust: nil)
    event = create(:party_event, :private_party, held_on: held_on, slot: slot)
    order = PartyOrderCreationService.new(
      customer: cust || customer, party_event: event,
      cart_items: [
        { "product_variant_id" => paton.id.to_s, "qty" => qty.to_s },
        { "product_variant_id" => forfait.id.to_s, "qty" => "1" }
      ]
    ).call
    order.update!(status: status)
    [ event, order ]
  end

  # --- Party publique -----------------------------------------------------
  let(:public_product) { create(:product, :pizza_party_public) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000) }
  let(:enfant) { create(:product_variant, product: public_product, name: "enfant", price_cents: 600) }

  def public_party(adults: 2, children: 3, status: :paid, cust: nil, event: nil)
    event ||= create(:party_event, :public_party, title: "Pizza Party de la rentrée", capacity: 40)
    items = []
    items << { "product_variant_id" => adulte.id.to_s, "qty" => adults.to_s } if adults.positive?
    items << { "product_variant_id" => enfant.id.to_s, "qty" => children.to_s } if children.positive?
    order = PartyOrderCreationService.new(customer: cust || customer, party_event: event, cart_items: items).call
    order.update!(status: status)
    [ event, order ]
  end

  describe "authentification" do
    it "refuse l'accès à la fiche sans être connecté" do
      event, = private_party

      get admin_party_event_path(event)

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "GET /admin/parties (réordonnancement)" do
    before { sign_in_admin }

    it "place les réservations privées AVANT les événements publics" do
      private_party
      public_party

      get admin_party_events_path

      expect(response).to have_http_status(:ok)
      private_pos = response.body.index("Réservations privées à venir")
      upcoming_pos = response.body.index("Événements publics à venir")
      past_pos = response.body.index("Événements publics passés")

      expect(private_pos).to be < upcoming_pos
      expect(upcoming_pos).to be < past_pos
    end

    it "garde les boutons d'action de l'en-tête" do
      get admin_party_events_path

      expect(response.body).to include("Créneaux privés (blocages)")
      expect(response.body).to include("Nouvel événement public")
    end

    it "montre le nombre de personnes et un lien vers la fiche" do
      event, = private_party(qty: 11)

      get admin_party_events_path

      expect(response.body).to include("Personnes")
      expect(response.body).to include("11")
      expect(response.body).to include(admin_party_event_path(event))
    end
  end

  describe "GET /admin/parties/:id — party PRIVÉE" do
    before { sign_in_admin }

    it "affiche date, créneau, client et nombre de personnes" do
      event, order = private_party(held_on: Date.new(2026, 9, 4), slot: :soir, qty: 11)

      get admin_party_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vendredi 4 septembre 2026")
      expect(response.body).to include("Soir")
      expect(response.body).to include("Alix Renard")
      expect(response.body).to include("alix@example.com")
      expect(response.body).to include("+32470111222")
      expect(response.body).to include("11")
      expect(response.body).to include(order.order_number)
      expect(response.body).to include(admin_order_path(order))
    end

    it "signale un four déjà chaud un jour de boulangerie (vendredi)" do
      event, = private_party(held_on: Date.new(2026, 9, 4))

      get admin_party_event_path(event)

      expect(response.body).to include("Four déjà chaud")
      expect(response.body).not_to include("chauffer le four")
    end

    it "prévient qu'il faudra chauffer le four un samedi" do
      event, = private_party(held_on: Date.new(2026, 9, 5))

      get admin_party_event_path(event)

      expect(response.body).to include("chauffer le four")
      expect(response.body).not_to include("Four déjà chaud")
    end

    it "dit explicitement qu'un client sans téléphone est identifié par email" do
      no_phone = create(:customer, first_name: "Sans", last_name: "Tel",
                                   email: "sans@example.com", phone_e164: nil,
                                   skip_phone_validation: true)
      event, = private_party(cust: no_phone)

      get admin_party_event_path(event)

      expect(response.body).to include("Aucun numéro de téléphone (client identifié par email)")
    end

    it "affiche une réservation annulée, avec son statut" do
      event, = private_party(status: :cancelled)

      get admin_party_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Annulée")
    end

    it "affiche une réservation encore en attente de paiement" do
      event, = private_party(status: :pending)

      get admin_party_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("En attente")
    end

    it "détaille les lignes de la commande (pâtons + forfait)" do
      event, = private_party(qty: 11)

      get admin_party_event_path(event)

      expect(response.body).to include("une boule")
      expect(response.body).to include("forfait")
    end
  end

  describe "GET /admin/parties/:id — party PUBLIQUE" do
    before { sign_in_admin }

    it "affiche l'identité de l'événement et la jauge" do
      event, = public_party(adults: 2, children: 3)

      get admin_party_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pizza Party de la rentrée")
      expect(response.body).to include("40")          # capacité
      expect(response.body).to include("Places prises")
      expect(response.body).to include("Places restantes")
    end

    it "liste les inscriptions avec adultes, enfants, contact et statut" do
      event, order = public_party(adults: 2, children: 3)

      get admin_party_event_path(event)

      expect(response.body).to include("Alix Renard")
      expect(response.body).to include("alix@example.com")
      expect(response.body).to include("Payée")
      expect(response.body).to include(admin_order_path(order))
    end

    it "affiche les totaux, annulées exclues" do
      event, = public_party(adults: 2, children: 3)
      other = create(:customer, first_name: "Marc", email: "marc@example.com")
      public_party(adults: 1, children: 0, cust: other, event: event)
      cancelled_cust = create(:customer, first_name: "Zoé", email: "zoe@example.com")
      public_party(adults: 5, children: 5, cust: cancelled_cust, event: event, status: :cancelled)

      get admin_party_event_path(event)

      expect(response.body).to include("Total (hors annulées)")
      # 2 + 1 adultes actifs, 3 + 0 enfants actifs — les 5/5 annulés sont exclus.
      expect(event.reload.seats_taken).to eq(6)
    end

    it "dit clairement qu'une party sans inscription est vide" do
      event = create(:party_event, :public_party, title: "Party déserte")

      get admin_party_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Personne ne s'est encore inscrit")
    end

    it "affiche une party historique par ses comptes agrégés, sans planter" do
      event = create(:party_event, :public_party, title: "BilletWeb 2024",
                                                  capacity: nil, registration_closes_at: nil,
                                                  historical_source: "BilletWeb",
                                                  historical_adults: 32, historical_children: 11,
                                                  historical_fees_cents: 4_500, historical_sourciers: 3)

      get admin_party_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ventes importées")
      expect(response.body).to include("32")
      expect(response.body).to include("11")
      expect(response.body).not_to include("Places prises")
    end

    it "signale un inscrit sans numéro de téléphone" do
      no_phone = create(:customer, first_name: "Sans", last_name: "Tel",
                                   email: "sans@example.com", phone_e164: nil,
                                   skip_phone_validation: true)
      event, = public_party(cust: no_phone)

      get admin_party_event_path(event)

      expect(response.body).to include("Aucun numéro")
    end
  end
end
