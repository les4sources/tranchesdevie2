require "rails_helper"

# #202 — signaler les pizza parties dans les commandes du jour de cuisson.
# « Fabienne, avec un petit pizza party noté à côté, et tu cliques, tu vas de
# suite à son détail » : le badge vit à côté du NOM DU CLIENT, dans le flux des
# commandes, et il est cliquable.
RSpec.describe "Admin — badge pizza party sur le jour de cuisson", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  let(:tuesday)  { Date.new(2026, 9, 1) }
  let(:friday)   { Date.new(2026, 9, 4) }
  let(:saturday) { Date.new(2026, 9, 5) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:tuesday_bake) { create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days) }
  let!(:friday_bake)  { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:customer) { create(:customer, first_name: "Fabienne", last_name: "Renard") }

  let(:private_product) { create(:product, :pizza_party, category: :dough_balls) }
  let(:paton) { create(:product_variant, product: private_product, name: "une boule", price_cents: 500, flour_quantity: 200) }

  let(:public_product) { create(:product, :pizza_party_public, category: :dough_balls) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, flour_quantity: 200) }

  def book(event:, variant:, qty:)
    order = PartyOrderCreationService.new(
      customer: customer, party_event: event,
      cart_items: [ { "product_variant_id" => variant.id.to_s, "qty" => qty.to_s } ]
    ).call
    order.update!(status: :paid)
    order
  end

  describe "party privée" do
    let!(:event) { create(:party_event, :private_party, held_on: friday, slot: :soir) }
    let!(:order) { book(event: event, variant: paton, qty: 11) }

    subject(:body) do
      get admin_bake_day_path(friday_bake)
      response.body
    end

    it "pose un badge « Party privée » à côté du nom du client, avec les pâtons et le créneau" do
      expect(body).to include("Fabienne Renard")
      expect(body).to include("Party privée · 11 pâtons · Soir")
    end

    it "rend le badge cliquable vers la fiche de l'événement" do
      expect(body).to include(%(href="#{admin_party_event_path(event)}"))
    end

    it "met le créneau en évidence dans l'encart, pas en tout petit" do
      expect(body).to include("11 pâtons au total")
      expect(body).to match(/Créneau.{0,120}Soir/m)
    end
  end

  describe "party publique" do
    let!(:event) { create(:party_event, :public_party, held_on: friday) }
    let!(:order) { book(event: event, variant: adulte, qty: 5) }

    subject(:body) do
      get admin_bake_day_path(friday_bake)
      response.body
    end

    it "porte un badge « Party publique », distinct de la privée" do
      expect(body).to include("Party publique")
      expect(body).not_to include("Party privée")
    end

    it "renvoie vers la fiche de l'événement public" do
      expect(body).to include(%(href="#{admin_party_event_path(event)}"))
    end
  end

  # Le badge doit apparaître là où les pâtons sont RÉELLEMENT pétris — donc sur
  # la fournée de préparation, pas sur le jour de la party (#170).
  describe "une party dont la préparation a lieu un autre jour" do
    let!(:event) { create(:party_event, :private_party, held_on: saturday, slot: :soir) }
    let!(:order) { book(event: event, variant: paton, qty: 7) }

    it "apparaît sur la fournée du vendredi, qui prépare le samedi" do
      get admin_bake_day_path(friday_bake)

      expect(response.body).to include("Party privée · 7 pâtons · Soir")
      expect(response.body).to include("pour le samedi 5 septembre 2026")
    end

    it "n'apparaît pas sur la fournée du mardi" do
      get admin_bake_day_path(tuesday_bake)

      expect(response.body).not_to include("Party privée")
    end
  end

  describe "non-régression : un jour sans party" do
    let!(:bread) { create(:product, :bread, name: "Pain froment") }
    let!(:variant) { create(:product_variant, product: bread, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650) }

    before do
      order = create(:order, :paid, customer: customer, bake_day: friday_bake, total_cents: 1_300)
      create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 650)
    end

    it "n'affiche aucun encart ni aucun badge party" do
      get admin_bake_day_path(friday_bake)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Pizza parties à préparer")
      expect(response.body).not_to include("Party privée")
      expect(response.body).not_to include("Party publique")
    end

    it "liste toujours la commande de pain dans le flux" do
      get admin_bake_day_path(friday_bake)

      expect(response.body).to include("Fabienne Renard")
      expect(response.body).to include("Voir la commande")
    end
  end
end
