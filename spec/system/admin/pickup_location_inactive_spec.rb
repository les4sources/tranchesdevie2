# frozen_string_literal: true

require "rails_helper"

# #199 — la démonstration demandée par la DoD : on désactive « Ferme de
# Champale » et on montre que la commande historique qui s'y rattache est
# intacte. Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — point de retrait désactivé", type: :system, browser_ui: true do
  PICKUP_PW = "demo-boulanger"
  PICKUP_SHOTS = Rails.root.join("tmp/shots")

  let!(:default_location) { create(:pickup_location, :default) }
  let!(:champale) { create(:pickup_location, name: "Ferme de Champale", description: "Dépôt chez Champale.", position: 5) }
  let(:bake_day) { create(:bake_day, :can_order) }

  before do
    ENV["ADMIN_PASSWORD"] = PICKUP_PW
    FileUtils.mkdir_p(PICKUP_SHOTS)

    flour = create(:flour, name: "Froment T65")
    product = create(:product, :bread, name: "Pain froment", channel: "store")
    create(:product_flour, product: product, flour: flour, percentage: 100)
    variant = create(:product_variant, product: product, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650, channel: "store")

    bake_day.pickup_location_ids = [ default_location.id, champale.id ]
    bake_day.save!

    customer = create(:customer, last_name: "Ancion", first_name: "Romane")
    order = create(:order, :paid, customer: customer, bake_day: bake_day, pickup_location: champale, total_cents: 1_950)
    create(:order_item, order: order, product_variant: variant, qty: 3, unit_price_cents: 650)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: PICKUP_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name, height = 800, selector: nil)
    page.driver.browser.manage.window.resize_to(1500, height)
    if selector
      page.execute_script("document.querySelector(arguments[0]).scrollIntoView({block: 'start'})", selector)
      page.execute_script("window.scrollBy(0, -24)")
    else
      page.execute_script("window.scrollTo(0, 0)")
    end
    sleep 0.4
    page.save_screenshot(PICKUP_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "se désactive depuis l'admin, et la commande historique reste intacte" do
    sign_in_admin

    visit "/admin/points-de-retrait/#{champale.id}/edit"
    expect(page).to have_text("Actif — proposé aux clients")
    uncheck "pickup_location[active]"
    click_button "Enregistrer"

    expect(page).to have_text("Inactif", wait: 10)
    expect(champale.reload.active?).to be false
    capture("retrait-1-liste")

    # L'historique : la commande est toujours là, dans la répartition du jour.
    visit "/admin/bake_days/#{bake_day.id}"
    find('button[data-tab="pickup"]').click

    expect(page).to have_text("Ferme de Champale")
    expect(page).to have_text("Lieu inactif")
    expect(page).to have_text("Romane Ancion")
    capture("retrait-2-historique", 900, selector: '[data-panel="pickup"]')
  end

  it "refuse de désactiver le lieu par défaut" do
    sign_in_admin
    visit "/admin/points-de-retrait/#{default_location.id}/edit"

    uncheck "pickup_location[active]"
    click_button "Enregistrer"

    expect(page).to have_text("Correction requise")
    expect(default_location.reload.active?).to be true
    capture("retrait-3-defaut-refuse")
  end
end
