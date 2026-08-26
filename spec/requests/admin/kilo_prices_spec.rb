require "rails_helper"

# #209 — saisie, correction et suppression des prix au kilo dans l'admin.
RSpec.describe "Admin::Settings::KiloPrices", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:figues) { create(:ingredient, name: "Figues") }
  let!(:froment) { create(:flour, name: "Froment T65", price_per_kg_cents: nil) }

  describe "les ingrédients" do
    it "listent leur historique de prix" do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.new(2026, 6, 1))
      create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))

      get admin_settings_ingredient_kilo_prices_path(figues)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Figues")
      expect(response.body).to include("10,00")
      expect(response.body).to include("14,00")
    end

    it "enregistrent un prix avec sa date d'effet" do
      expect {
        post admin_settings_ingredient_kilo_prices_path(figues),
             params: { kilo_price: { amount_euros: "12,50", active_from: "2026-06-01" } }
      }.to change(IngredientPrice, :count).by(1)

      price = IngredientPrice.last
      expect(response).to redirect_to(admin_settings_ingredient_kilo_prices_path(figues))
      expect(price.amount_cents).to eq(1_250)
      expect(price.active_from).to eq(Date.new(2026, 6, 1))
    end

    it "refusent un prix sans date d'effet" do
      post admin_settings_ingredient_kilo_prices_path(figues),
           params: { kilo_price: { amount_euros: "12,50", active_from: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "corrigent un prix" do
      price = create(:ingredient_price, ingredient: figues, amount_cents: 10_000, active_from: Date.new(2026, 6, 1))

      patch admin_settings_ingredient_kilo_price_path(figues, price),
            params: { kilo_price: { amount_euros: "10,00", active_from: "2026-06-01" } }

      expect(price.reload.amount_cents).to eq(1_000)
    end

    it "suppriment un prix" do
      price = create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.new(2026, 8, 1))

      expect { delete admin_settings_ingredient_kilo_price_path(figues, price) }
        .to change(IngredientPrice, :count).by(-1)
    end

    it "affichent le prix courant et le lien depuis la liste des ingrédients" do
      create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.current - 1)

      get admin_settings_ingredients_path

      expect(response.body).to include("14,00")
      expect(response.body).to include(admin_settings_ingredient_kilo_prices_path(figues))
    end

    it "signalent un ingrédient sans prix" do
      get admin_settings_ingredients_path

      expect(response.body).to include("aucun prix")
    end
  end

  describe "les farines" do
    it "utilisent le même écran" do
      create(:flour_price, flour: froment, amount_cents: 95, active_from: Date.new(2026, 7, 1))

      get admin_settings_flour_kilo_prices_path(froment)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Froment T65")
      expect(response.body).to include("0,95")
    end

    it "enregistrent un prix" do
      expect {
        post admin_settings_flour_kilo_prices_path(froment),
             params: { kilo_price: { amount_euros: "0,95", active_from: "2026-07-01" } }
      }.to change(FlourPrice, :count).by(1)

      expect(FlourPrice.last.amount_cents).to eq(95)
    end

    it "renvoient vers l'historique depuis le formulaire de la farine" do
      get edit_admin_settings_flour_path(froment)

      expect(response.body).to include(admin_settings_flour_kilo_prices_path(froment))
      expect(response.body).to include("Gérer l&#39;historique des prix")
    end
  end

  describe "le rapport de coût des matières" do
    let!(:default_pickup) { create(:pickup_location, :default) }

    it "répond et affiche les coûts valorisés" do
      product = create(:product, :bread, name: "Pain aux figues")
      create(:product_flour, product: product, flour: froment, percentage: 100)
      variant = create(:product_variant, product: product, name: "Grand", flour_quantity: 1_000, price_cents: 650)
      VariantIngredient.create!(product_variant: variant, ingredient: figues, quantity: 50)
      create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.current - 60)
      create(:flour_price, flour: froment, amount_cents: 80, active_from: Date.current - 60)

      date = Date.current - 10
      bake_day = create(:bake_day, baked_on: date, cut_off_at: date - 2.days)
      order = create(:order, :paid, customer: create(:customer), bake_day: bake_day, total_cents: 10 * 650)
      create(:order_item, order: order, product_variant: variant, qty: 10, unit_price_cents: 650)

      get ingredient_costs_admin_reports_path(start_date: Date.current - 30, end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coût des matières premières")
      expect(response.body).to include("Figues")
      expect(response.body).to include("Froment T65")
      expect(response.body).to include("5,00")  # 0,5 kg de figues à 10 €
      expect(response.body).to include("8,00")  # 10 kg de farine à 0,80 €
    end

    it "signale les éléments non valorisés" do
      get ingredient_costs_admin_reports_path(start_date: Date.current - 30, end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Éléments sans prix")
    end
  end
end
