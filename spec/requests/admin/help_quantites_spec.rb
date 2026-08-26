require "rails_helper"

# #211 — le chapitre d'aide « Régler les quantités et les recettes ».
RSpec.describe "Admin — centre d'aide, chapitre quantités", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:slug) { "quantites-et-recettes" }

  describe "le sommaire" do
    it "liste le nouveau chapitre avec son vrai titre" do
      # /admin/aide redirige vers le premier chapitre ; le sommaire est rendu
      # dans la barre latérale de chaque chapitre.
      get admin_help_path
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Régler les quantités et les recettes")
      # Un front-matter cassé ferait retomber sur un titre dérivé du nom de
      # fichier : c'est précisément ce qu'on veut exclure.
      expect(response.body).not_to include("Quantites Et Recettes")
      expect(response.body).not_to include("quantites-et-recettes.md")
    end
  end

  describe "le chapitre" do
    subject(:body) do
      get admin_help_article_path(slug)
      response.body
    end

    it "répond" do
      body
      expect(response).to have_http_status(:ok)
    end

    it "explique la quantité de pâte d'une variante et son effet" do
      expect(body).to include("Quantité de pâte requise")
      expect(body).to include("panification")
      expect(body).to include("n&#39;est <strong>pas</strong> le poids du pain cuit").or include("pas</strong> le poids du pain cuit")
    end

    it "explique les ratios de panification et la convention retenue" do
      expect(body).to include("Ratio de panification")
      expect(body).to include("fractions de la PÂTE")
      expect(body).to include("0,532")
    end

    it "explique comment retirer un produit, et dit ce qui n'est pas faisable" do
      expect(body).to include("Restriction par jour")
      expect(body).to include("cet écran n&#39;existe pas encore").or include("écran n'existe pas encore")
    end

    it "rappelle la méthode de vérification par commande de test" do
      expect(body).to include("commande de test")
      expect(body).to include("Supprimez la commande de test")
      expect(body).to include("4,26 kg")
    end

    it "référence ses captures" do
      expect(body).to include("product-variant-edit")
      expect(body).to include("settings-flour-edit")
    end
  end

  describe "la navigation" do
    it "expose un lien précédent depuis le chapitre" do
      get admin_help_article_path(slug)

      # Le chapitre est le dernier (order 11) : il a un précédent, pas de suivant.
      expect(response.body).to include("Les paramètres")
    end

    it "reste atteignable depuis le chapitre voisin" do
      get admin_help_article_path("parametres")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Régler les quantités et les recettes")
    end
  end

  describe "le manifeste des captures" do
    it "déclare les deux nouveaux slugs" do
      manifest = YAML.safe_load_file(Rails.root.join("app/docs/aide/screenshots.yml"))
      slugs = manifest.map { |entry| entry["slug"] }

      expect(slugs).to include("product-variant-edit", "settings-flour-edit")
    end

    it "ne référence aucune capture absente du manifeste" do
      manifest = YAML.safe_load_file(Rails.root.join("app/docs/aide/screenshots.yml"))
      declared = manifest.map { |entry| entry["slug"] }.to_set

      referenced = Dir[Rails.root.join("app/docs/aide/*.md")].flat_map do |path|
        File.read(path).scan(/\(shot:([a-z0-9-]+)\)/).flatten
      end.uniq

      expect(referenced - declared.to_a).to be_empty
    end
  end
end
