require "rails_helper"

# Marqueur « compter séparément » sur la variante (#151) : édition admin et
# affichage de la sous-ligne dans le planning du jour de cuisson.
RSpec.describe "Admin — décompte séparé de variante", type: :request do
  let!(:grand) { MoldType.create!(name: "Grand", limit: 95, position: 1) }
  let!(:production_setting) do
    ProductionSetting.create!(oven_capacity_grams: 100_000, market_day_oven_capacity_grams: 200_000)
  end
  let(:product) { create(:product, category: :breads) }
  let(:variant) { create(:product_variant, product: product, name: "XXL (1,4 kg)", mold_type: grand) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_PASSWORD").and_return("secret")
    post admin_login_path, params: { password: "secret" }
  end

  it "affiche la case à cocher sur le formulaire d'édition de variante" do
    get edit_variant_admin_product_path(product, variant)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Compter séparément")
  end

  it "persiste le marqueur via la mise à jour de la variante" do
    patch variant_admin_product_path(product, variant), params: {
      product_variant: { name: variant.name, track_capacity_separately: "1" }
    }

    expect(variant.reload.track_capacity_separately).to be(true)
  end

  it "affiche la sous-ligne « dont … » dans le planning du jour de cuisson" do
    variant.update!(track_capacity_separately: true)
    bake_day = create(:bake_day)
    order = create(:order, :paid, bake_day: bake_day)
    create(:order_item, order: order, product_variant: variant, qty: 4)

    get admin_bake_day_path(bake_day)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dont")
    expect(response.body).to include("XXL (1,4 kg)")
  end
end
