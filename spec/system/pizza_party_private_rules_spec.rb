# frozen_string_literal: true

require "rails_helper"

# #201 — la DoD demande la preuve visuelle : le calendrier ouvert pour de vrai,
# où seuls des mardis et des vendredis soir sont sélectionnables.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Pizza party privée — calendrier", type: :system, browser_ui: true do
  PARTY_SHOTS = Rails.root.join("tmp/shots")

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:party_product) { create(:product, :pizza_party, channel: "store", name: "Pizza party privée – Nombre de personnes") }
  let!(:party_variant) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, channel: "store") }
  let!(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait Pizza party privée") }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4000, channel: "store") }

  before { FileUtils.mkdir_p(PARTY_SHOTS) }

  def capture(name, height, selector: nil)
    page.driver.browser.manage.window.resize_to(1400, height)
    if selector
      page.execute_script("document.querySelector(arguments[0]).scrollIntoView({block: 'start'})", selector)
      page.execute_script("window.scrollBy(0, -24)")
    else
      page.execute_script("window.scrollTo(0, 0)")
    end
    sleep 0.5
    page.save_screenshot(PARTY_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "ne rend sélectionnables que des mardis et des vendredis" do
    visit "/pizza-party-privee"
    expect(page).to have_text("Choisis ta date")

    # Tous les jours cliquables du calendrier, lus dans le DOM.
    wdays = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('[data-party-calendar-target="day"]'))
        .map((el) => new Date(el.dataset.date + 'T12:00:00').getDay())
    JS

    expect(wdays).not_to be_empty
    # 2 = mardi, 5 = vendredi (getDay : 0 = dimanche).
    expect(wdays.uniq.sort).to eq([ 2, 5 ])

    capture("party-1-calendrier", 1100, selector: "#reserver")
  end

  it "n'offre plus que le créneau du soir une fois la date choisie" do
    visit "/pizza-party-privee"
    first('[data-party-calendar-target="day"]').click

    labels = page.all('[data-party-calendar-target="slotButton"]').map(&:text)

    expect(labels).to eq([ "Soir" ])
    expect(page).to have_text("le four est déjà chaud")
    capture("party-2-creneau", 1000, selector: '[data-party-calendar-target="slotPanel"]')
  end

  it "affiche les nouveaux textes du « Bon à savoir »" do
    visit "/pizza-party-privee"

    expect(page).to have_text("mardi soir et le vendredi soir")
    expect(page).to have_text("jusqu'à la veille 16 h")
    expect(page).to have_text("n'inclut pas la location d'une salle")
    expect(page).to have_text(BakeryDetails::PHONE_DISPLAY)
    expect(page).to have_no_text("3 heures de chauffe")

    capture("party-3-bon-a-savoir", 780, selector: ".mt-10.rounded-2xl")
  end
end
