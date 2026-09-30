# frozen_string_literal: true

require "rails_helper"

# Modale « Ma commande du … » du calendrier, sur un petit téléphone.
#
# Bug remonté en prod : avec plusieurs points de retrait ouverts (4 Sources,
# marché, Champalle), le bouton « Enregistrer » sortait de la modale sans qu'on
# puisse défiler jusqu'à lui — commande impossible à valider.
#
# Selenium défile tout seul jusqu'à un élément avant de cliquer, même dans un
# conteneur `overflow: hidden` qu'un doigt ne ferait pas bouger : on vérifie
# donc la position du bouton AVANT le clic, sans rien faire défiler.
RSpec.describe "Calendrier — modale sur mobile", type: :system do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:customer) { create(:customer, phone_e164: "+32470#{rand(100_000..999_999)}", calendar_intro_seen_at: Time.current) }
  let(:bake_day) { create(:bake_day, :can_order, baked_on: Date.current.next_occurring(:friday) + 7) }
  let(:market) { create(:pickup_location, name: "Marché de Ciney", description: "Au stand de la boulangerie, place Monseigneur Cawet, de 8 h à 12 h 30.") }
  let(:champalle) { create(:pickup_location, name: "Champalle", description: "À la ferme de Champalle, dans le frigo de l'entrée, à partir de 17 h.") }

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before do
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    create(:wallet, customer: customer, balance_cents: 50_000)
    bake_day.pickup_locations << [ market, champalle ]

    # Assez de produits pour que la liste, à elle seule, dépasse l'écran.
    8.times do |n|
      product = create(:product, :bread, name: "Pain n°#{n + 1}")
      create(:product_variant, product: product, name: "800 g", price_cents: 500 + n)
    end
  end

  def sign_in
    visit "/connexion"
    fill_in "identifier", with: customer.phone_e164
    click_button "Recevoir mon code"
    fill_in "otp_code", with: "123456"
    click_button "Vérifier le code"
    expect(page).to have_current_path(customers_account_path, wait: 10)
  end

  # Rectangle du bouton comparé à la fenêtre, sans défilement.
  def fully_in_viewport?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector(#{selector.to_json}).getBoundingClientRect()
        return r.top >= 0 && r.bottom <= window.innerHeight && r.height > 0
      })()
    JS
  end

  it "garde « Enregistrer » à portée de doigt et enregistre la commande" do
    sign_in
    # Écran d'iPhone SE, une fois connecté.
    page.driver.browser.manage.window.resize_to(375, 667)
    visit calendar_path

    click_button "Commander", match: :first
    expect(page).to have_css("[data-calendar-target='saveBtn']", visible: true)

    # Dès l'ouverture, avant tout geste : le titre ET le bouton tiennent à l'écran.
    expect(fully_in_viewport?("[data-calendar-target='modalTitle']")).to be(true)
    expect(fully_in_viewport?("[data-calendar-target='saveBtn']")).to be(true)

    find("[data-variant-id]", match: :first).find("[data-action='click->calendar#incrementQty']").click

    # Point de retrait : un menu déroulant, pas une pile de cartes.
    select "Champalle", from: "calendar_pickup_location"
    expect(page).to have_text("À la ferme de Champalle")

    FileUtils.mkdir_p(Rails.root.join("tmp/shots"))
    page.save_screenshot(Rails.root.join("tmp/shots/calendar-modal-mobile.png").to_s)

    expect(fully_in_viewport?("[data-calendar-target='modalTitle']")).to be(true)
    expect(fully_in_viewport?("[data-calendar-target='saveBtn']")).to be(true)

    find("[data-calendar-target='saveBtn']").click
    expect(page).to have_css("[data-calendar-target='modalSuccess']:not(.hidden)", wait: 10)

    order = customer.orders.find_by(bake_day: bake_day)
    expect(order.pickup_location).to eq(champalle)
  end
end
