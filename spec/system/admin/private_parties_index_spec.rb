# frozen_string_literal: true

require "rails_helper"

# #205 — la DoD demande de montrer côte à côte l'écran Parties et le rapport,
# sur une même période, et de démontrer qu'ils concordent.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — écran Parties et rapport", type: :system, browser_ui: true do
  IDX_PW = "demo-boulanger"
  IDX_SHOTS = Rails.root.join("tmp/shots")

  let(:today) { Date.current }
  let!(:default_pickup) { create(:pickup_location, :default) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait") }
  let!(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store") }

  before do
    ENV["ADMIN_PASSWORD"] = IDX_PW
    FileUtils.mkdir_p(IDX_SHOTS)
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: paton, amount_cents: 26, active_from: today - 400)

    # Trois parties passées SANS événement — le cas des 17 de production…
    [ [ "Romane Ancion", 20, 6 ], [ "Thomas Bastin", 35, 10 ], [ "Stéphanie Colot", 50, 8 ] ].each do |name, days_ago, qty|
      customer = create(:customer, first_name: name.split.first, last_name: name.split.last)
      baked_on = today - days_ago
      bake_day = create(:bake_day, baked_on: baked_on, cut_off_at: baked_on - 2.days)
      order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: qty * 500)
      create(:order_item, order: order, product_variant: paton, qty: qty, unit_price_cents: 500)
    end

    # …et une party à venir, réservée en ligne, avec son événement.
    customer = create(:customer, first_name: "Fabienne", last_name: "Renard")
    event = create(:party_event, :private_party, held_on: today + 7, slot: :soir)
    order = create(:order, :paid, customer: customer, bake_day: nil, party_event: event,
                                  source: :party, total_cents: 8 * 500 + 4_000)
    create(:order_item, order: order, product_variant: paton, qty: 8, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait, qty: 1, unit_price_cents: 4_000)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: IDX_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name, height)
    page.driver.browser.manage.window.resize_to(1600, height)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(IDX_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "retrouve les parties privées passées et sans événement, en accord avec le rapport" do
    sign_in_admin
    visit "/admin/parties"

    expect(page).to have_text("Pizza parties privées passées")
    expect(page).to have_text("Romane Ancion")
    expect(page).to have_text("Thomas Bastin")
    expect(page).to have_text("Stéphanie Colot")
    expect(page).to have_text("Sans événement")
    expect(page).to have_text("Fabienne Renard")
    capture("parties-1-ecran", 1150)

    visit "/admin/reports/pizza_parties?start_date=#{today - 60}&end_date=#{today - 1}"
    expect(page).to have_text("Romane Ancion")
    capture("parties-2-rapport", 1000)

    # Concordance : mêmes commandes, mêmes montants.
    report_ids = OrderItem.joins(product_variant: :product)
                          .where(products: { pizza_party_role: Product.pizza_party_roles[:party] })
                          .select(:order_id)
    report_orders = Order.completed.in_bake_day_range(today - 60, today - 1).where(id: report_ids).to_a
    screen_orders = Admin::PrivatePartyIndex.new.past
                                            .select { |e| e.held_on&.between?(today - 60, today - 1) }
                                            .map(&:order)

    expect(screen_orders.map(&:id).sort).to eq(report_orders.map(&:id).sort)
    expect(screen_orders.sum(&:total_cents)).to eq(report_orders.sum(&:total_cents))
  end
end
