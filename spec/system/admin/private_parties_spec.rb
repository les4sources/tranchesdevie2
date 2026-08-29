# frozen_string_literal: true

require "rails_helper"

# #204 — création à la main d'une party privée, dans un navigateur.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — party privée créée à la main", type: :system, browser_ui: true do
  PRIV_PW = "demo-boulanger"
  PRIV_SHOTS = Rails.root.join("tmp/shots")

  let(:date) { Date.current.next_occurring(:friday) + 7 }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait") }
  let!(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store") }

  before do
    ENV["ADMIN_PASSWORD"] = PRIV_PW
    FileUtils.mkdir_p(PRIV_SHOTS)
    flour = create(:flour, name: "Froment T65")
    create(:product_flour, product: party_product, flour: flour, percentage: 100)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: PRIV_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
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
    page.save_screenshot(PRIV_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "crée une party convenue par mail, non payée, et la marque payée" do
    sign_in_admin
    visit "/admin/parties"

    click_link "Nouvelle party privée"
    expect(page).to have_text("Nouvelle pizza party privée")

    fill_in "private_party[held_on]", with: date.strftime("%d/%m/%Y")
    fill_in "private_party[persons]", with: "8"
    fill_in "private_party[name]", with: "Fabienne Renard"
    fill_in "private_party[email]", with: "fabienne@example.test"
    uncheck "private_party[paid]"
    capture("privee-1-formulaire", 1000)

    click_button "Créer la party"
    expect(page).to have_text("Pizza party privée créée.")
    expect(page).to have_text("Ajoutée à la main")
    capture("privee-2-fiche", 700)

    event = PartyEvent.private_events.last
    order = event.orders.last
    expect(order.paid?).to be false
    expect(order.total_cents).to eq(8 * 500 + 4_000)
    expect(order.customer.phone_e164).to be_nil

    # Elle est bien annoncée sur le jour de cuisson.
    visit "/admin/bake_days/#{bake_day.id}"
    expect(page).to have_text("Pizza parties à préparer")
    expect(page).to have_text("Fabienne Renard")
    capture("privee-3-jour-de-cuisson", 620, selector: ".adm-card")

    visit "/admin/parties/#{event.id}"
    click_button "Marquer payée"
    expect(page).to have_text("Party marquée payée.")
    expect(order.reload.paid?).to be true
  end
end
