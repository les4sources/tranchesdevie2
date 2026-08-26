# frozen_string_literal: true

require "rails_helper"

# #202 — les captures demandées par la DoD : un jour avec party privée, un jour
# avec party publique. Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — signalétique des pizza parties", type: :system, browser_ui: true do
  BADGE_PW = "demo-boulanger"
  BADGE_SHOTS = Rails.root.join("tmp/shots")

  let(:friday) { Date.current.next_occurring(:friday) + 7 }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:friday_bake) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  before do
    ENV["ADMIN_PASSWORD"] = BADGE_PW
    FileUtils.mkdir_p(BADGE_SHOTS)

    flour = create(:flour, name: "Froment T65")
    bread = create(:product, :bread, name: "Pain froment")
    create(:product_flour, product: bread, flour: flour, percentage: 100)
    variant = create(:product_variant, product: bread, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650)

    eater = create(:customer, first_name: "Romane", last_name: "Ancion")
    order = create(:order, :paid, customer: eater, bake_day: friday_bake, total_cents: 1_950)
    create(:order_item, order: order, product_variant: variant, qty: 3, unit_price_cents: 650)

    @customer = create(:customer, first_name: "Fabienne", last_name: "Renard")
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: BADGE_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def book(event:, variant:, qty:)
    order = PartyOrderCreationService.new(
      customer: @customer, party_event: event,
      cart_items: [ { "product_variant_id" => variant.id.to_s, "qty" => qty.to_s } ]
    ).call
    order.update!(status: :paid)
    order
  end

  def capture(name, height, selector: nil)
    page.driver.browser.manage.window.resize_to(1500, height)
    if selector
      page.execute_script("document.querySelector(arguments[0]).scrollIntoView({block: 'start'})", selector)
      page.execute_script("window.scrollBy(0, -24)")
    else
      page.execute_script("window.scrollTo(0, 0)")
    end
    sleep 0.4
    page.save_screenshot(BADGE_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "affiche l'encart et le badge d'une party PRIVÉE" do
    event = create(:party_event, :private_party, held_on: friday, slot: :soir)
    book(event: event, variant: create(:product_variant, product: create(:product, :pizza_party, category: :dough_balls), name: "une boule", price_cents: 500, flour_quantity: 200), qty: 11)

    sign_in_admin
    visit "/admin/bake_days/#{friday_bake.id}"

    expect(page).to have_text("Pizza parties à préparer")
    expect(page).to have_text("11 pâtons au total")
    capture("party-badge-1-privee-encart", 520, selector: "#parties-a-preparer")

    find('button[data-tab="timeline"]').click
    expect(page).to have_text("Party privée · 11 pâtons · Soir")
    capture("party-badge-2-privee-flux", 620, selector: '[data-panel="timeline"]')
  end

  it "affiche l'encart et le badge d'une party PUBLIQUE" do
    event = create(:party_event, :public_party, held_on: friday)
    book(event: event, variant: create(:product_variant, product: create(:product, :pizza_party_public, category: :dough_balls), name: "adulte", price_cents: 1_000, flour_quantity: 200), qty: 6)

    sign_in_admin
    visit "/admin/bake_days/#{friday_bake.id}"

    expect(page).to have_text("Party publique")
    capture("party-badge-4-publique-encart", 520, selector: "#parties-a-preparer")

    find('button[data-tab="timeline"]').click
    expect(page).to have_text("Party publique")
    capture("party-badge-3-publique-flux", 620, selector: '[data-panel="timeline"]')
  end
end
