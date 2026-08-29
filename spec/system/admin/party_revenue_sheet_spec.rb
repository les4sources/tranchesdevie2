# frozen_string_literal: true

require "rails_helper"

# #207 — la preuve à l'écran : la feuille compta du jour affiche désormais la
# ligne party d'une réservation faite en ligne.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — feuille compta et pizza party en ligne", type: :system, browser_ui: true do
  SHEET_PW = "demo-boulanger"
  SHEET_SHOTS = Rails.root.join("tmp/shots")

  let(:friday) { Date.new(2026, 9, 4) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  before do
    ENV["ADMIN_PASSWORD"] = SHEET_PW
    FileUtils.mkdir_p(SHEET_SHOTS)

    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))

    party_product = create(:product, :pizza_party, name: "Pizza party privée")
    paton = create(:product_variant, product: party_product, name: "1 boule", price_cents: 500, flour_quantity: 200, channel: "store")
    create(:variant_cost_price, product_variant: paton, amount_cents: 26, active_from: friday - 60)
    forfait_product = create(:product, :pizza_party_forfait, name: "Forfait Pizza party privée")
    forfait = create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store")

    artisan = create(:artisan, name: "Romane")
    create(:artisan_revenue_share, artisan: artisan, percent: 100, active_from: Date.new(2026, 1, 1))
    create(:bake_day_artisan, bake_day: bake_day, artisan: artisan)

    flour = create(:flour, name: "Froment T65")
    bread = create(:product, :bread, name: "Pain froment")
    create(:product_flour, product: bread, flour: flour, percentage: 100)
    variant = create(:product_variant, product: bread, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650)
    create(:variant_cost_price, product_variant: variant, amount_cents: 200, active_from: friday - 60)
    bread_order = create(:order, :paid, customer: create(:customer, last_name: "Ancion", first_name: "Romane"),
                                        bake_day: bake_day, total_cents: 20 * 650)
    create(:order_item, order: bread_order, product_variant: variant, qty: 20, unit_price_cents: 650)

    # La party réservée EN LIGNE : bake_day nil, rattachée à son événement.
    event = create(:party_event, :private_party, held_on: friday, slot: :soir)
    @party_order = create(:order, :paid, customer: create(:customer, last_name: "Renard", first_name: "Fabienne"),
                                         bake_day: nil, party_event: event, source: :party,
                                         total_cents: 11 * 500 + 4_000)
    create(:order_item, order: @party_order, product_variant: paton, qty: 11, unit_price_cents: 500)
    create(:order_item, order: @party_order, product_variant: forfait, qty: 1, unit_price_cents: 4_000)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: SHEET_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  it "affiche la ligne party dans la feuille compta du jour" do
    expect(@party_order.bake_day_id).to be_nil

    sign_in_admin
    visit "/admin/bake_days/#{bake_day.id}/sheet"

    expect(page).to have_text("Feuille compta")
    # 11 personnes, 95,00 € — la party est bien là.
    expect(page).to have_text("95,00")

    page.driver.browser.manage.window.resize_to(1500, 1150)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(SHEET_SHOTS.join("compta-party.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end
end
