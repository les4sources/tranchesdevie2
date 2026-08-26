# frozen_string_literal: true

require "rails_helper"

# #197 — le jour de cuisson brouillon, vu de l'écran. Exclu du run normal
# (tag :browser_ui) parce qu'il exige Chrome.
RSpec.describe "Admin — jour de cuisson en brouillon", type: :system, browser_ui: true do
  DRAFT_PW = "demo-boulanger"
  DRAFT_SHOTS = Rails.root.join("tmp/shots")

  let(:tuesday) { Date.current.next_occurring(:tuesday) }

  before do
    ENV["ADMIN_PASSWORD"] = DRAFT_PW
    FileUtils.mkdir_p(DRAFT_SHOTS)

    flour = create(:flour, name: "Froment T65")
    product = create(:product, :bread, name: "Pain froment")
    create(:product_flour, product: product, flour: flour, percentage: 100)
    @variant = create(:product_variant, product: product, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650)

    @real_day = create(:bake_day, baked_on: tuesday)
    @draft_day = create(:bake_day, :draft, baked_on: tuesday + 3.days)

    [ @real_day, @draft_day ].each do |day|
      customer = create(:customer, last_name: "Ancion", first_name: "Romane")
      order = create(:order, :paid, customer: customer, bake_day: day, total_cents: 3_250)
      create(:order_item, order: order, product_variant: @variant, qty: 5, unit_price_cents: 650)
    end
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: DRAFT_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name, height = 780)
    page.driver.browser.manage.window.resize_to(1500, height)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(DRAFT_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "se distingue dans la liste, sur sa page, et sur sa feuille compta" do
    sign_in_admin

    visit "/admin/bake_days"
    expect(page).to have_text("Brouillon")
    capture("brouillon-1-liste")

    visit "/admin/bake_days/#{@draft_day.id}"
    expect(page).to have_text("Brouillon — hors comptabilité")
    # Les calculs tournent : 5 × 800 g.
    expect(page).to have_text("4000 g")
    capture("brouillon-2-page")

    visit "/admin/bake_days/#{@draft_day.id}/sheet"
    expect(page).to have_text("Cette feuille n'est PAS comptabilisée.")
    capture("brouillon-3-feuille")
  end

  it "expose la case à cocher au formulaire de création" do
    sign_in_admin
    visit "/admin/bake_days/new"

    expect(page).to have_field("bake_day[draft]", visible: :all)
    expect(page).to have_text("Brouillon")
    capture("brouillon-4-formulaire", 900)
  end
end
