require "rails_helper"

# #camembert-parties — commande 2154 : une place de Camembert Party ajoutée à une
# commande de pain restait attachée à la fournée, sans événement, et n'était
# pas comptée dans les participants. Le formulaire ne la propose plus.
RSpec.describe "Admin::Orders — produits party", type: :request do
  let!(:pickup) { create(:pickup_location, :default) }
  let(:bread) { create(:product, :bread, name: "Pain au froment") }
  let!(:bread_variant) { create(:product_variant, product: bread, name: "Grand 1 kg", price_cents: 550) }
  let(:party_product) { create(:product, :pizza_party_public, category: :dough_balls, name: "Camembert Party publique") }
  let!(:adult) { create(:product_variant, product: party_product, name: "adulte", price_cents: 1_000) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_PASSWORD").and_return("secret")
    post admin_login_path, params: { password: "secret" }
  end

  it "ne propose pas les places de party dans une nouvelle commande, et renvoie vers la fiche de la party" do
    get new_admin_order_path

    expect(response.body).to include("Pain au froment")
    expect(response.body).not_to include("Camembert Party publique")
    expect(response.body).to include("Ajouter une inscription")
  end

  it "garde à l'édition une ligne party déjà présente, et la signale" do
    order = create(:order, :unpaid, bake_day: create(:bake_day), customer: create(:customer), total_cents: 1_000)
    create(:order_item, order: order, product_variant: adult, qty: 5, unit_price_cents: 1_000)

    get edit_admin_order_path(order)

    expect(response.body).to include("Camembert Party publique")
    expect(response.body).to include("Cette commande contient une place de party")
  end
end
