require "rails_helper"

# #196 — la matrice clients × variantes de l'onglet « Commandes par client ».
# Une variante au nom long élargissait sa colonne à elle seule : les largeurs
# passent en `<colgroup>` + `table-layout: fixed`.
RSpec.describe "Admin::BakeDays — matrice clients × variantes", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:bake_day) { create(:bake_day) }
  let(:product) { create(:product, :bread, name: "Pain classique") }
  let(:customer) { create(:customer, last_name: "Ancion", first_name: "Romane") }

  let!(:long_variant) { create(:product_variant, product: product, name: "Classique 800 gr rond cuit sur pierre", price_cents: 650) }
  let!(:short_variants) do
    4.times.map { |i| create(:product_variant, product: product, name: "Format #{i}", price_cents: 400 + i) }
  end

  before do
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 2_000)
    create(:order_item, order: order, product_variant: long_variant, qty: 2, unit_price_cents: 650)
    short_variants.each { |variant| create(:order_item, order: order, product_variant: variant, qty: 1, unit_price_cents: variant.price_cents) }
  end

  subject(:body) do
    get admin_bake_day_path(bake_day)
    response.body
  end

  it "rend la matrice avec la variante au nom long" do
    body
    expect(response).to have_http_status(:ok)
    expect(body).to include("Classique 800 gr rond cuit sur pierre")
  end

  it "déclare une largeur par colonne dans un colgroup — une par variante, plus le client et le total" do
    matrix = body[/<table class="adm-grid adm-grid-matrix">.*?<\/colgroup>/m]

    expect(matrix).to be_present
    # 5 variantes + la colonne client + la colonne Total.
    expect(matrix.scan(/<col /).size).to eq(7)
  end

  it "ne pose plus de largeur en ligne sur les cellules de la matrice" do
    matrix = body[/<table class="adm-grid adm-grid-matrix">.*?<\/table>/m]

    expect(matrix).not_to include("width: 100px")
    expect(matrix).not_to include("width: 50px")
  end

  it "garde le prix sous le nom de variante, les colspan produits et les colonnes figées" do
    matrix = body[/<table class="adm-grid adm-grid-matrix">.*?<\/table>/m]

    expect(matrix).to include("6,50 €")
    expect(matrix).to include("colspan=\"5\"")
    expect(matrix).to include("position: sticky; left: 0;")
    expect(matrix).to include("position: sticky; right: 0;")
  end
end
