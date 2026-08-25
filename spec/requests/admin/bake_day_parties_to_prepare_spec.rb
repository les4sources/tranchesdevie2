require "rails_helper"

# Bloc « Pizza parties à préparer » du tableau de bord d'une fournée (#170).
RSpec.describe "Admin — Pizza parties à préparer", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  let(:tuesday)  { Date.new(2026, 9, 1) }
  let(:friday)   { Date.new(2026, 9, 4) }
  let(:saturday) { Date.new(2026, 9, 5) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:tuesday_bake) { create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days) }
  let!(:friday_bake)  { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:customer) { create(:customer, first_name: "Alix", last_name: "Renard") }
  let(:party_product) { create(:product, :pizza_party, category: :dough_balls) }
  let(:paton) do
    create(:product_variant, product: party_product, name: "une boule",
                             price_cents: 500, flour_quantity: 200)
  end

  def book_party(held_on:, slot:, qty: 11, status: :paid)
    event = create(:party_event, :private_party, held_on: held_on, slot: slot)
    order = PartyOrderCreationService.new(
      customer: customer, party_event: event,
      cart_items: [ { "product_variant_id" => paton.id.to_s, "qty" => qty.to_s } ]
    ).call
    order.update!(status: status)
    order
  end

  it "affiche le bloc avec date, créneau, nombre de personnes et client" do
    book_party(held_on: friday, slot: :soir, qty: 11)

    get admin_bake_day_path(friday_bake)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pizza parties à préparer")
    expect(response.body).to include("Soir")
    expect(response.body).to include("11")
    expect(response.body).to include("Alix Renard")
  end

  it "signale qu'une party a lieu le jour même" do
    book_party(held_on: friday, slot: :soir)

    get admin_bake_day_path(friday_bake)

    expect(response.body).to include(CGI.escapeHTML("Aujourd'hui"))
  end

  it "annonce la date d'une party qui a lieu plus tard" do
    book_party(held_on: saturday, slot: :soir)

    get admin_bake_day_path(friday_bake)

    expect(response.body).to include("à préparer pour le")
    expect(response.body).to include("samedi 5 septembre 2026")
  end

  it "n'affiche aucun bloc quand la fournée n'a pas de party à préparer" do
    get admin_bake_day_path(friday_bake)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Pizza parties à préparer")
  end

  it "montre une party de midi sur la fournée précédente, pas sur celle du jour" do
    book_party(held_on: friday, slot: :midi)

    get admin_bake_day_path(tuesday_bake)
    expect(response.body).to include("Pizza parties à préparer")

    get admin_bake_day_path(friday_bake)
    expect(response.body).not_to include("Pizza parties à préparer")
  end

  it "n'affiche pas une party annulée" do
    book_party(held_on: friday, slot: :soir, status: :cancelled)

    get admin_bake_day_path(friday_bake)

    expect(response.body).not_to include("Pizza parties à préparer")
  end
end
