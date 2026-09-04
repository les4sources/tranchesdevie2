require "rails_helper"

# Le point de retrait sur les drapeaux (#253) : lisible d'un coup d'œil sur la
# carte, sans quitter l'onglet pour croiser « Par point de retrait ».
RSpec.describe "Admin — drapeaux et point de retrait", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:bake_day) { create(:bake_day) }
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée", position: 1) }
  let(:variant) { create(:product_variant) }

  before do
    bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
    bake_day.save!
  end

  def place_order(customer, location)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, pickup_location: location)
    create(:order_item, order: order, product_variant: variant, qty: 1)
    order
  end

  subject(:body) do
    get admin_bake_day_path(bake_day)
    response.body
  end

  it "nomme le lieu non-défaut sur la carte du client" do
    place_order(create(:customer, last_name: "Zorro"), anhee)

    expect(body).to include(CGI.escapeHTML(anhee.name))
    expect(body).to include("adm-flag-pickup")
  end

  it "n'applique pas le badge appuyé au lieu par défaut" do
    place_order(create(:customer, last_name: "Dupont"), default_location)

    expect(body).to include(CGI.escapeHTML(default_location.name))
    expect(body).not_to include("adm-flag-pickup")
  end

  it "affiche les deux lieux d'un client qui a deux commandes à deux endroits" do
    customer = create(:customer, last_name: "Martin")
    place_order(customer, anhee)
    place_order(customer, default_location)

    expect(body).to include(CGI.escapeHTML(anhee.name))
    expect(body).to include(CGI.escapeHTML(default_location.name))
    expect(body).to include("adm-flag-pickup")
  end

  it "rend la page sans planter quand le lieu d'une commande est soft-deleted" do
    place_order(create(:customer, last_name: "Leroy"), anhee)
    anhee.soft_delete!

    get admin_bake_day_path(bake_day)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML(anhee.name))
  end

  # Décision de cadrage : l'onglet « Par point de retrait » RESTE, avec sa
  # feuille de retrait PDF. Les drapeaux le complètent, ils ne le remplacent pas.
  describe "l'onglet « Par point de retrait »" do
    it "garde ses lieux et son lien vers la feuille de retrait" do
      place_order(create(:customer, last_name: "Zorro"), anhee)

      expect(body).to include('data-panel="pickup"')
      expect(body).to include(CGI.escapeHTML(anhee.name))
      expect(body).to include(CGI.escapeHTML(default_location.name))
      expect(body).to include(pickup_sheet_admin_bake_day_path(bake_day, pickup_location_id: anhee.id))
    end
  end
end
