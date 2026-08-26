# frozen_string_literal: true

require "rails_helper"

# #195 — les consignes du jour dans une modale, pilotées pour de vrai.
# Ce qu'on vérifie ici, c'est la promesse : une consigne saisie dans la modale
# reste visible sur la page une fois la modale fermée, et après rechargement.
#
# Exclu du run normal (tag :browser_ui) parce qu'il exige Chrome.
RSpec.describe "Admin — consignes du jour", type: :system, browser_ui: true do
  NOTE_PW = "demo-boulanger"
  NOTE_SHOTS = Rails.root.join("tmp/shots")

  let(:bake_day) { create(:bake_day) }

  before do
    ENV["ADMIN_PASSWORD"] = NOTE_PW
    FileUtils.mkdir_p(NOTE_SHOTS)

    flour = create(:flour, name: "Froment T65")
    product = create(:product, :bread, name: "Pain froment")
    create(:product_flour, product: product, flour: flour, percentage: 100)
    variant = create(:product_variant, product: product, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650)

    customer = create(:customer, last_name: "Ancion", first_name: "Romane")
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1_950)
    create(:order_item, order: order, product_variant: variant, qty: 3, unit_price_cents: 650)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: NOTE_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture_top(name)
    page.driver.browser.manage.window.resize_to(1600, 820)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(NOTE_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "saisit une consigne dans la modale, et la garde visible après fermeture puis rechargement" do
    sign_in_admin
    visit "/admin/bake_days/#{bake_day.id}"

    expect(page).to have_text("Aucune consigne")
    expect(page).to have_text("Rien de particulier aujourd'hui.")
    capture_top("consignes-1-vide")

    click_button "Ajouter"
    expect(page).to have_css("trix-editor", visible: true)
    capture_top("consignes-2-modale")

    find("trix-editor").click
    find("trix-editor").send_keys("Pâte en retard : décaler l'enfournement de 30 minutes.")
    expect(page).to have_text("Note enregistrée", wait: 10)

    click_button "Terminé"
    expect(page).to have_no_css("trix-editor", visible: true)

    # Le point dur de l'issue : la consigne reste lisible SANS ouvrir la modale.
    expect(page).to have_text("Consigne active")
    expect(page).to have_text("Pâte en retard : décaler l'enfournement de 30 minutes.")
    expect(page).to have_no_text("Rien de particulier aujourd'hui.")

    expect(bake_day.reload.internal_note).to include("Pâte en retard")

    visit "/admin/bake_days/#{bake_day.id}"
    expect(page).to have_text("Consigne active")
    expect(page).to have_text("Pâte en retard : décaler l'enfournement de 30 minutes.")
    capture_top("consignes-3-rempli")
  end

  it "ne perd pas une saisie en cours quand on ferme la modale aussitôt" do
    sign_in_admin
    visit "/admin/bake_days/#{bake_day.id}"

    click_button "Ajouter"
    find("trix-editor").click
    find("trix-editor").send_keys("Livraison de farine à 6 h.")
    # On ferme AVANT l'expiration du délai de sauvegarde différée (800 ms).
    click_button "Fermer"

    expect(page).to have_text("Note enregistrée", wait: 10)
    expect(bake_day.reload.internal_note).to include("Livraison de farine à 6 h.")

    visit "/admin/bake_days/#{bake_day.id}"
    expect(page).to have_text("Livraison de farine à 6 h.")
  end
end
