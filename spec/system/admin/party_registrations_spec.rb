# frozen_string_literal: true

require "rails_helper"

# #203 — l'ajout à la main, joué dans un navigateur.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — inscription manuelle sur une party publique", type: :system, browser_ui: true do
  REG_PW = "demo-boulanger"
  REG_SHOTS = Rails.root.join("tmp/shots")

  let(:date) { Date.current.next_occurring(:friday) + 7 }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let(:product) { create(:product, :pizza_party_public, name: "Pizza party publique") }
  let!(:adulte) { create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300) }
  let!(:enfant) { create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200) }
  let!(:event) { create(:party_event, :public_party, held_on: date, capacity: 30, title: "Pizza party de septembre") }

  before do
    ENV["ADMIN_PASSWORD"] = REG_PW
    FileUtils.mkdir_p(REG_SHOTS)

    # Une inscription faite EN LIGNE, pour montrer la distinction.
    customer = create(:customer, first_name: "Romane", last_name: "Ancion")
    web = PublicPartyRegistrationService.new(
      customer: customer, party_event: event,
      cart_items: [ { "product_variant_id" => adulte.id.to_s, "qty" => "2" } ],
      payment_method: "cash"
    ).call
    web.update!(status: :paid)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: REG_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name, height, selector: nil)
    page.driver.browser.manage.window.resize_to(1600, height)
    if selector
      page.execute_script("document.querySelector(arguments[0]).scrollIntoView({block: 'start'})", selector)
      page.execute_script("window.scrollBy(0, -24)")
    else
      page.execute_script("window.scrollTo(0, 0)")
    end
    sleep 0.4
    page.save_screenshot(REG_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "ajoute une inscription non payée, puis la marque payée" do
    sign_in_admin
    visit "/admin/parties/#{event.id}"

    click_link "Ajouter une inscription"
    expect(page).to have_text("Ajouter une inscription")

    fill_in "registration[name]", with: "Fabienne Renard"
    fill_in "registration[adults]", with: "2"
    fill_in "registration[children]", with: "1"
    capture("inscription-1-formulaire", 780)

    click_button "Ajouter l'inscription"
    expect(page).to have_text("Inscription ajoutée.")

    # Distinguable de l'inscription en ligne, et non payée.
    expect(page).to have_text("Manuelle")
    expect(page).to have_text("Fabienne Renard")
    expect(page).to have_text("Marquer payée")
    capture("inscription-2-liste", 700, selector: "table.adm-grid")

    order = Order.find_by(manually_added: true)
    expect(order.paid?).to be false
    expect(event.reload.seats_taken).to eq(5)

    click_button "Marquer payée"
    expect(page).to have_text("Inscription marquée payée.")
    expect(order.reload.paid?).to be true
    capture("inscription-3-payee", 700, selector: "table.adm-grid")
  end
end
