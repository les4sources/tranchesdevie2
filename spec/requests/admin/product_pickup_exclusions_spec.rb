require "rails_helper"

# Admin produit (#152) : cocher les lieux de retrait exclus d'un produit.
RSpec.describe "Admin — exclusions produit / lieu de retrait", type: :request do
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }
  let(:product) { create(:product, name: "Pain surprise") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_PASSWORD").and_return("secret")
    post admin_login_path, params: { password: "secret" }
  end

  it "affiche la section des lieux exclus sur le formulaire produit" do
    get edit_admin_product_path(product)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lieux de retrait exclus")
    expect(response.body).to include(CGI.escapeHTML("Marché d'Anhée"))
  end

  it "persiste les exclusions cochées" do
    patch admin_product_path(product), params: {
      product: { name: product.name, category: product.category,
                 internal_category: product.internal_category, position: product.position,
                 channel: product.channel, excluded_pickup_location_ids: [ anhee.id, "" ] }
    }

    expect(product.reload.excluded_pickup_locations).to contain_exactly(anhee)
  end

  it "retire une exclusion quand elle est décochée" do
    product.excluded_pickup_locations << anhee

    patch admin_product_path(product), params: {
      product: { name: product.name, category: product.category,
                 internal_category: product.internal_category, position: product.position,
                 channel: product.channel, excluded_pickup_location_ids: [ "" ] }
    }

    expect(product.reload.excluded_pickup_locations).to be_empty
  end
end
