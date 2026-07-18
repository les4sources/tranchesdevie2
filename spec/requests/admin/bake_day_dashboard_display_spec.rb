require "rails_helper"

# Vérifie le rendu des évolutions d'affichage du planning « jour de cuisson » :
# - prix de vente public sous chaque variante dans l'en-tête (tâche #4)
# - prix réellement payé (remise appliquée) dans les drapeaux (tâche #5)
# - ligne « Total » figée dans le thead sticky (tâche #8)
# - type de levain affiché dans le bloc Panification (tâche #11)
RSpec.describe "Admin::BakeDays dashboard — affichage", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  # Client dans un groupe à 10 % de remise : prix public 5,50 € → payé 4,95 €.
  let(:flour) { create(:flour, levain_type: "froment") }
  let(:product) { create(:product, :bread, name: "Pain au froment") }
  let!(:product_flour) { create(:product_flour, product: product, flour: flour, percentage: 100) }
  let(:variant) { create(:product_variant, product: product, name: "1 kg", price_cents: 550, flour_quantity: 1000) }
  let(:bake_day) { create(:bake_day) }
  let(:customer) { create(:customer, last_name: "Zorro", first_name: "Alba") }
  let(:group) { create(:group, discount_percent: 10) }

  before do
    create(:customer_group, customer: customer, group: group)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 990)
    create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 550)
  end

  subject(:body) do
    get admin_bake_day_path(bake_day)
    response.body
  end

  it "affiche le prix de vente public sous la variante dans l'en-tête (#4)" do
    expect(response_ok(body)).to be true
    expect(body).to include("5,50 €") # prix public de la variante
  end

  it "affiche le prix réellement payé (remise 10 % appliquée) dans les drapeaux (#5)" do
    body
    expect(body).to include("9,90 €")   # 2 × (5,50 − 0,55) = ligne payée
    expect(body).to include("4,95 € / u") # prix unitaire remisé
  end

  it "place la ligne « Total » à l'intérieur du thead sticky (#8)" do
    doc = Nokogiri::HTML(body)
    thead = doc.at_css('div[data-panel="clients"] table thead')
    expect(thead).to be_present
    # La ligne total porte la classe bg-slate-200 : sa présence dans le thead
    # prouve qu'elle est figée avec l'en-tête (et non dans le tbody scrollable).
    expect(thead.to_html).to include("bg-slate-200")
    expect(thead.text).to include("Total")
  end

  it "affiche le type de levain dans le bloc Panification (#11)" do
    body
    expect(body).to include("Type de levain")
    expect(body).to include("levain froment")
  end

  def response_ok(_body)
    response.status == 200
  end
end
