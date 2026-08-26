require "rails_helper"

# #205 — l'écran Parties retrouve les parties privées : celles qui sont passées,
# et celles enregistrées sans `PartyEvent`.
RSpec.describe "Admin — écran Parties, parties privées", type: :request do
  include ActionView::Helpers::NumberHelper

  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:today) { Date.current }
  let!(:default_pickup) { create(:pickup_location, :default) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait") }
  let!(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store") }

  def party_with_event(held_on:, qty: 8, name: "Fabienne Renard")
    customer = create(:customer, first_name: name.split.first, last_name: name.split.last)
    event = create(:party_event, :private_party, held_on: held_on, slot: :soir)
    order = create(:order, :paid, customer: customer, bake_day: nil, party_event: event,
                                  source: :party, total_cents: qty * 500 + 4_000)
    create(:order_item, order: order, product_variant: paton, qty: qty, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait, qty: 1, unit_price_cents: 4_000)
    [ event, order ]
  end

  def party_without_event(baked_on:, qty: 8, name: "Romane Ancion")
    customer = create(:customer, first_name: name.split.first, last_name: name.split.last)
    bake_day = BakeDay.find_by(baked_on: baked_on) || create(:bake_day, baked_on: baked_on, cut_off_at: baked_on - 2.days)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: qty * 500)
    create(:order_item, order: order, product_variant: paton, qty: qty, unit_price_cents: 500)
    order
  end

  subject(:body) do
    get admin_party_events_path
    response.body
  end

  it "liste une party privée PASSÉE — elle ne disparaît plus le lendemain" do
    party_with_event(held_on: today - 10, name: "Fabienne Renard")

    expect(body).to include("Pizza parties privées passées")
    expect(body).to include("Fabienne Renard")
  end

  it "liste une party enregistrée SANS événement, avec un lien vers sa commande" do
    order = party_without_event(baked_on: today - 30, name: "Romane Ancion")

    expect(body).to include("Romane Ancion")
    expect(body).to include("Sans événement")
    expect(body).to include(admin_order_path(order))
  end

  it "affiche date, client, pâtons, montant et forfait" do
    party_with_event(held_on: today + 7, qty: 8)

    expect(body).to include("Pâtons")
    expect(body).to include("Montant")
    expect(body).to include("Forfait")
    expect(body).to include("8")
    # 8 pâtons à 5 € + 40 € de forfait.
    expect(body).to include(CGI.escapeHTML(number_to_currency(80.0, unit: "€", separator: ",", delimiter: " ")))
    expect(body).to include("Oui")
  end

  it "renvoie vers la fiche de l'événement quand il existe" do
    event, = party_with_event(held_on: today + 7)

    expect(body).to include(admin_party_event_path(event))
  end

  it "sépare les parties à venir des parties passées" do
    party_with_event(held_on: today + 7, name: "Future Party")
    party_without_event(baked_on: today - 30, name: "Ancienne Party")

    expect(body).to include("Réservations privées à venir")
    expect(body).to include("Pizza parties privées passées")
    expect(body.index("Réservations privées à venir")).to be < body.index("Pizza parties privées passées")
  end

  it "n'affiche pas les parties annulées" do
    _, order = party_with_event(held_on: today + 7, name: "Annulée Party")
    order.update!(status: :cancelled)

    expect(body).not_to include("Annulée Party")
  end

  # Le critère central : mêmes parties, mêmes montants que le rapport.
  it "concorde avec le rapport pizza_parties sur la même période" do
    3.times { |i| party_without_event(baked_on: today - (10 + i * 5), qty: 4 + i) }

    start_date = today - 60
    end_date = today - 1

    get pizza_parties_admin_reports_path(start_date: start_date, end_date: end_date)
    expect(response).to have_http_status(:ok)

    report_ids = OrderItem.joins(product_variant: :product)
                          .where(products: { pizza_party_role: Product.pizza_party_roles[:party] })
                          .select(:order_id)
    report_orders = Order.completed.in_bake_day_range(start_date, end_date).where(id: report_ids).to_a

    screen_orders = Admin::PrivatePartyIndex.new.past
                                            .select { |e| e.held_on&.between?(start_date, end_date) }
                                            .map(&:order)

    expect(screen_orders.map(&:id).sort).to eq(report_orders.map(&:id).sort)
    expect(screen_orders.sum(&:total_cents)).to eq(report_orders.sum(&:total_cents))
  end
end
