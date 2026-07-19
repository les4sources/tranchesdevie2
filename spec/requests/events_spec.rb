require "rails_helper"

# Page publique « Événements » (#pizza-parties) : la pizza party privée se
# réserve ici, hors du catalogue produits.
RSpec.describe "Événements", type: :request do
  def party_product
    product = create(:product, :pizza_party,
                     name: "Pizza party privée – Nombre de personnes",
                     description: "Une boule de pâte à pizza par personne.")
    create(:product_variant, product: product, name: "une boule", price_cents: 500)
    product
  end

  describe "GET /evenements" do
    it "affiche la réservation quand la party est disponible" do
      party_product
      get evenements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pizza Party")
      expect(response.body).to include("Nombre de personnes")
      expect(response.body).to include("Réserver ma Pizza Party")
      expect(response.body).to include(cart_add_path)
    end

    it "affiche un état « bientôt » quand aucune party n'est disponible" do
      get evenements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nos événements arrivent bientôt.")
    end
  end

  describe "catalogue" do
    it "ne liste PAS la pizza party privée (elle est sur Événements)" do
      party = party_product
      bread = create(:product, :bread, name: "Pain au froment")
      create(:product_variant, product: bread, price_cents: 550)

      get catalog_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pain au froment")
      expect(response.body).not_to include(party.name)
    end
  end

  describe "GET /productions/:id pour la party" do
    it "redirige la fiche produit vers /evenements" do
      party = party_product

      get product_path(party)

      expect(response).to redirect_to(evenements_path)
    end
  end
end
