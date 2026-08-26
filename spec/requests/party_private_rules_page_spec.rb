require "rails_helper"

# #201 — les textes de la page publique de réservation, et le refus SERVEUR
# d'un jour ou d'un créneau non autorisé (pas seulement un masquage dans l'UI).
RSpec.describe "Pizza party privée — règles et textes", type: :request do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:party_product) { create(:product, :pizza_party, channel: "store", name: "Pizza party privée – Nombre de personnes") }
  let!(:party_variant) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, channel: "store") }
  let!(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait Pizza party privée") }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4000, channel: "store") }

  let(:tuesday) { Date.current.next_occurring(:tuesday) + 7 }
  let(:wednesday) { tuesday + 1 }

  subject(:body) do
    get pizza_party_privee_path
    response.body
  end

  describe "les mentions supprimées" do
    it "ne parle plus des 3 heures de chauffe" do
      expect(body).not_to include("3 heures")
      expect(body).not_to include("heures de chauffe")
    end

    it "ne parle plus de réserver au moins une semaine à l'avance" do
      expect(body).not_to include("au moins une semaine")
    end

    it "ne demande plus les allergies ni les enfants dans la note" do
      expect(body).not_to include("allergies")
      expect(body).not_to include("sans gluten")
    end
  end

  describe "les mentions ajoutées" do
    it "annonce le mardi soir et le vendredi soir" do
      expect(body).to include("mardi soir et le vendredi soir")
    end

    it "annonce la limite de réservation à la veille 16 h" do
      expect(body).to include("veille 16 h")
    end

    it "précise que la location de salle n'est pas incluse, avec le lien vers Les 4 Sources" do
      expect(body).to include("n'inclut pas la location d'une salle")
      expect(body).to include("https://www.les4sources.be")
    end

    it "invite à téléphoner, avec le numéro cliquable" do
      expect(body).to include("Téléphone-nous")
      expect(body).to include(%(href="tel:#{BakeryDetails::PHONE_E164}"))
      expect(body).to include(BakeryDetails::PHONE_DISPLAY)
    end

    it "demande l'occasion et l'heure d'arrivée dans la note" do
      expect(body).to include("Quelle est l'occasion")
      expect(body).to include("À quelle heure arrivez-vous")
      expect(body).to include("anniversaire de Jules, on arrive vers 18h30")
    end
  end

  # Le masquage dans l'UI ne suffit pas : une requête forgée doit être refusée.
  describe "le refus côté serveur" do
    let(:customer) { create(:customer) }

    def add_to_cart(date, slot)
      post cart_add_path, params: {
        product_variant_id: party_variant.id,
        party_slot_choice: "#{date.iso8601}|#{slot}",
        party_note: "On arrive vers 18h30.",
        qty: 4
      }
    end

    it "accepte un mardi soir" do
      add_to_cart(tuesday, "soir")

      expect(session[:party_date]).to eq(tuesday.iso8601)
      expect(response).to redirect_to(cart_path)
    end

    it "refuse un mercredi soir" do
      add_to_cart(wednesday, "soir")

      expect(session[:cart].to_a).to be_empty
      expect(response).to redirect_to(pizza_party_privee_path)
    end

    it "refuse le créneau de midi, même un mardi" do
      add_to_cart(tuesday, "midi")

      expect(session[:cart].to_a).to be_empty
      expect(response).to redirect_to(pizza_party_privee_path)
    end

    it "refuse aussi au niveau du service de réservation" do
      service = PartyReservationService.new(
        customer: customer,
        date: wednesday.iso8601,
        slot: "soir",
        cart_items: [ { "product_variant_id" => party_variant.id, "qty" => 4 } ],
        payment_method: "cash",
        customer_note: "On arrive vers 18h30."
      )

      expect(service.call).to be false
      expect(service.errors.join).to include("créneau")
    end
  end
end
