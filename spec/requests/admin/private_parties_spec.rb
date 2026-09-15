require "rails_helper"

# #204 — création à la main d'une pizza party privée depuis l'admin.
RSpec.describe "Admin::PrivateParties", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:date) { Date.new(2026, 9, 4) }
  let(:wednesday) { Date.new(2026, 9, 2) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait") }
  let!(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store") }

  def create_party(persons: 8, held_on: date, slot: "soir", name: "Fabienne Renard", forfait_on: "1", paid: "1", **rest)
    post admin_private_parties_path, params: {
      private_party: { held_on: held_on.to_s, slot: slot, persons: persons, name: name,
                       forfait: forfait_on, paid: paid }.merge(rest)
    }
  end

  describe "l'accès" do
    it "propose le bouton depuis l'écran Parties" do
      get admin_party_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nouvelle party privée")
      expect(response.body).to include(new_admin_private_party_path)
    end

    it "affiche le formulaire" do
      get new_admin_private_party_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nouvelle pizza party privée")
      expect(response.body).to include("private_party[persons]")
      expect(response.body).to include("Inclure le forfait")
    end
  end

  describe "POST create" do
    it "crée la party avec un nouveau client sans téléphone" do
      expect { create_party(persons: 8, name: "Fabienne Renard") }
        .to change(PartyEvent, :count).by(1)

      event = PartyEvent.last
      order = event.orders.last

      expect(response).to redirect_to(admin_party_event_path(event))
      expect(event.kind_private_party?).to be true
      expect(order.manually_added?).to be true
      expect(order).to be_payment_status_paid
      expect(order.customer.phone_e164).to be_nil
      expect(order.total_cents).to eq(8 * 500 + 4_000)
    end

    it "apparaît dans l'écran Parties, comme celles venues du site" do
      create_party(persons: 8)

      get admin_party_events_path

      expect(response.body).to include("Fabienne Renard")
    end

    it "apparaît sur le jour de cuisson avec ses pâtons" do
      create_party(persons: 8)

      get admin_bake_day_path(bake_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pizza parties à préparer")
      expect(response.body).to include("Fabienne Renard")
    end

    it "ré-affiche le formulaire avec ses erreurs quand la saisie est incomplète" do
      create_party(persons: 0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Correction requise")
    end

    it "accepte un créneau bloqué pour le client — les règles client ne s'appliquent pas à l'admin" do
      PartySlotBlock.create!(blocked_on: wednesday, slot: "midi", reason: "Fermé")

      expect { create_party(held_on: wednesday, slot: "midi", persons: 6) }
        .to change(PartyEvent, :count).by(1)

      expect(PartyEvent.last.slot).to eq("midi")
    end
  end

  describe "la fiche de la party" do
    before { create_party(persons: 8, paid: "0") }

    subject(:body) do
      get admin_party_event_path(PartyEvent.last)
      response.body
    end

    it "porte le badge « Ajoutée à la main » et les actions" do
      event = PartyEvent.last

      expect(body).to include("Ajoutée à la main")
      expect(body).to include(edit_admin_private_party_path(event))
      # L'encaissement sur place passe par le chemin unique de pointage, qui
      # trace le MOYEN — plus de bascule « payée / non payée » (#pizza-parties).
      expect(body).to include("Encaissée en liquide")
      expect(body).to include("Encaissée par virement")
    end
  end

  describe "encaissement sur place" do
    it "pointe le moyen et sait revenir en arrière" do
      create_party(persons: 8, paid: "0")
      order = PartyEvent.last.orders.last
      expect(order).to be_payment_status_unpaid

      patch encaissement_admin_order_path(order, method: "cash")
      order.reload
      expect(order).to be_payment_status_paid
      expect(order.offline_payment_method).to eq("cash")

      patch encaissement_admin_order_path(order, method: "none")
      order.reload
      expect(order).to be_payment_status_unpaid
      expect(order.offline_payment_method).to be_nil
    end

    it "refuse de pointer une réservation déjà payée en ligne" do
      create_party(persons: 8, paid: "0")
      order = PartyEvent.last.orders.last
      create(:payment, order: order, status: :succeeded)

      patch encaissement_admin_order_path(order, method: "cash")

      # Rien n'est pointé : l'app a vu l'argent passer par Stripe, elle a raison
      # contre le bouton.
      expect(order.reload.offline_payment_method).to be_nil
    end
  end

  describe "édition d'une réservation venue du site" do
    it "est refusée : elle porte un PaymentIntent engagé chez Stripe" do
      create_party(persons: 8, paid: "0")
      event = PartyEvent.last
      event.orders.last.update!(payment_intent_id: "pi_en_ligne")

      get edit_admin_private_party_path(event)

      expect(response).to redirect_to(admin_party_event_path(event))
      follow_redirect!
      expect(response.body).to include("payée ou engagée en ligne")
    end
  end

  describe "PATCH update" do
    it "modifie la date, le créneau et les effectifs" do
      create_party(persons: 8)
      event = PartyEvent.last
      order = event.orders.last

      patch admin_private_party_path(event), params: {
        private_party: { held_on: wednesday.to_s, slot: "midi", persons: 4,
                         customer_id: order.customer_id, forfait: "0", paid: "1" }
      }

      expect(response).to redirect_to(admin_party_event_path(event))
      expect(event.reload.held_on).to eq(wednesday)
      expect(event.slot).to eq("midi")
      expect(order.reload.total_cents).to eq(4 * 500)
    end
  end

  describe "DELETE destroy" do
    it "supprime la party et sa commande" do
      create_party(persons: 8)
      event = PartyEvent.last

      expect { delete admin_private_party_path(event) }.to change(PartyEvent, :count).by(-1)

      expect(response).to redirect_to(admin_party_events_path)
      expect(Order.where(party_event_id: event.id)).to be_empty
    end
  end
end
