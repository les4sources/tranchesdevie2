require "rails_helper"

# Le formulaire de feedback Tally de l'écran de confirmation reçoit le nom du
# client via un champ caché « nom » (à déclarer tel quel dans l'éditeur Tally).
RSpec.describe "Feedback Tally après achat", type: :request do
  let(:bake_day) { create(:bake_day, :can_order) }

  def tally_src
    Nokogiri::HTML(response.body).at_css("iframe[data-tally-src]")["data-tally-src"]
  end

  def tally_query
    Rack::Utils.parse_query(URI.parse(tally_src).query)
  end

  it "passe le nom complet du client, encodé, au formulaire" do
    customer = create(:customer, first_name: "Léa", last_name: "D'Hondt & fils")
    order = create(:order, :with_items, customer: customer, bake_day: bake_day)

    get "/checkout/success", params: { order_token: order.public_token }

    expect(response).to have_http_status(:ok)
    expect(tally_src).to start_with("https://tally.so/embed/yPPAbX?")
    expect(tally_query).to include("nom" => "Léa D'Hondt & fils", "hideTitle" => "1", "dynamicHeight" => "1")
  end

  it "se contente du prénom quand le nom de famille manque" do
    customer = create(:customer, first_name: "Léa", last_name: nil)
    order = create(:order, :with_items, customer: customer, bake_day: bake_day)

    get "/checkout/success", params: { order_token: order.public_token }

    expect(tally_query["nom"]).to eq("Léa")
  end
end
