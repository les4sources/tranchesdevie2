require "rails_helper"

RSpec.describe "Admin::BakeDays", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  # #71 : le planning du jour de cuisson contient la matrice « Commandes par client »
  # (produits en colonnes) dont l'en-tête doit rester figé au défilement. On vérifie
  # ici que la page rend sans erreur quand il y a au moins une commande (la matrice
  # est alors affichée), suite au passage du conteneur en scroll vertical.
  describe "GET /admin/bake_days/:id" do
    it "rend le planning avec la matrice commandes par client sans erreur" do
      bake_day = create(:bake_day)
      customer = create(:customer)
      product = create(:product, :bread)
      variant = create(:product_variant, product: product, price_cents: 550)
      order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1100)
      create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 550)

      get admin_bake_day_path(bake_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Commandes par client")
    end
  end
end
