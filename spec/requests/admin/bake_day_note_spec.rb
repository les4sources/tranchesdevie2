require "rails_helper"

# #195 — les consignes du jour passent dans une modale. Le risque de la modale,
# c'est qu'une consigne saisie devienne invisible : ces specs vérifient donc
# surtout que l'état (vide / rempli) et l'aperçu restent lisibles SANS ouvrir la
# modale, et que l'enregistrement différé continue de répondre.
RSpec.describe "Admin::BakeDays — consignes du jour", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:bake_day) { create(:bake_day) }

  subject(:body) do
    get admin_bake_day_path(bake_day)
    response.body
  end

  context "sans consigne enregistrée" do
    it "affiche l'état vide en clair, et propose d'en ajouter une" do
      body
      expect(response).to have_http_status(:ok)
      expect(body).to include("Aucune consigne")
      expect(body).to include("Rien de particulier aujourd'hui.")
      expect(body).not_to include("Consigne active")
    end
  end

  context "avec une consigne enregistrée" do
    before { bake_day.update!(internal_note: "<div>Pâte en retard : décaler l'enfournement de 30 minutes.</div>") }

    it "affiche la pastille active ET l'aperçu du texte, sans ouvrir la modale" do
      body
      expect(response).to have_http_status(:ok)
      expect(body).to include("Consigne active")
      expect(body).to include("Pâte en retard : décaler l&#39;enfournement de 30 minutes.")
      expect(body).not_to include("Aucune consigne")
    end

    it "masque le libellé « rien de particulier »" do
      expect(body).to match(/class="text-sm hidden"[^>]*data-bake-day-note-target="placeholder"/)
    end
  end

  context "une consigne qui ne contient que du balisage vide" do
    before { bake_day.update!(internal_note: "<div><br></div>") }

    it "compte comme vide plutôt que comme consigne active" do
      expect(body).to include("Aucune consigne")
      expect(body).not_to include("Consigne active")
    end
  end

  describe "l'éditeur et ses commandes" do
    it "vivent dans la modale, avec l'enregistrement différé et le bouton manuel" do
      expect(body).to include('data-bake-day-note-target="modal"')
      expect(body).to include("trix-change-&gt;bake-day-note#queueSave")
      expect(body).to include("Enregistrer maintenant")
      expect(body).to include("Dernière mise à jour")
    end
  end

  describe "PATCH /admin/bake_days/:id" do
    it "enregistre la consigne et répond en JSON à la sauvegarde différée" do
      patch admin_bake_day_path(bake_day),
            params: { bake_day: { internal_note: "<div>Livraison de farine à 6 h.</div>" } },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("bake_day", "internal_note")).to include("Livraison de farine à 6 h.")
      expect(bake_day.reload.internal_note).to include("Livraison de farine à 6 h.")
    end
  end
end
