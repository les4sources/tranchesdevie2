require "rails_helper"

# Alerte « Capacité four » côté admin : le bandeau sur les autres pages, le bloc
# de décision sur la fiche du jour, et les deux choix des boulangers.
RSpec.describe "Admin::OvenBatchPlans", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:bake_day) { create(:bake_day) }
  let(:variant) { create(:product_variant, product: create(:product, :bread), flour_quantity: 1_000) }

  # Des pains de 1 kg pour `kg` kilos au four — comme des commandes internes.
  def fill_oven(kg)
    order = create(:order, :paid, customer: create(:customer), bake_day: bake_day, total_cents: 1_000)
    create(:order_item, order: order, product_variant: variant, qty: kg)
  end

  describe "le bandeau de l'admin" do
    it "signale un jour à 120 kg sur les autres pages, avec un lien vers sa fiche" do
      fill_oven(122)

      get admin_bake_days_path

      expect(response.body).to include('data-role="oven-batch-banner"')
      expect(response.body).to include("122 kg de pain au four, deux fournées pleines ou une 3e fournée ?")
      expect(response.body).to include(admin_bake_day_path(bake_day))
    end

    it "reste absent sous 120 kg" do
      fill_oven(115)

      get admin_bake_days_path

      expect(response.body).not_to include('data-role="oven-batch-banner"')
    end

    it "laisse la place au bloc de décision sur la fiche du jour" do
      fill_oven(122)

      get admin_bake_day_path(bake_day)

      expect(response.body).not_to include('data-role="oven-batch-banner"')
      expect(response.body).to include("Encore 8 kg et les deux fournées seront pleines.")
      expect(response.body).to include("Rester à 2 fournées", "Ouvrir une 3e fournée")
    end
  end

  describe "PATCH update" do
    before { fill_oven(122) }

    it "valide deux fournées pleines et fait taire l'alerte" do
      patch admin_bake_day_oven_batch_plan_path(bake_day), params: { plan: 2 }

      expect(response).to redirect_to(admin_bake_day_path(bake_day))
      expect(bake_day.reload.oven_batch_plan).to eq(2)
      expect(bake_day.oven_batch_plan_decided_at).to be_present

      get admin_bake_days_path
      expect(response.body).not_to include('data-role="oven-batch-banner"')
    end

    it "ouvre une 3e fournée" do
      patch admin_bake_day_oven_batch_plan_path(bake_day), params: { plan: 3 }

      expect(bake_day.reload.oven_batch_plan).to eq(3)
      follow_redirect!
      expect(response.body).to include("3e fournée ouverte : l&#39;horaire de production s&#39;allonge.")
    end

    it "refuse de rester à deux fournées au-delà de 130 kg" do
      fill_oven(10)

      patch admin_bake_day_oven_batch_plan_path(bake_day), params: { plan: 2 }

      expect(bake_day.reload.oven_batch_plan).to be_nil
      follow_redirect!
      expect(response.body).to include("Le four dépasse déjà 130 kg")
    end

    it "refuse un choix inconnu" do
      patch admin_bake_day_oven_batch_plan_path(bake_day), params: { plan: 4 }

      expect(bake_day.reload.oven_batch_plan).to be_nil
    end
  end
end
