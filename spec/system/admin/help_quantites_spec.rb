# frozen_string_literal: true

require "rails_helper"

# #211 — le chapitre d'aide, ouvert pour de vrai : sommaire, contenu, captures.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — chapitre d'aide « quantités et recettes »", type: :system, browser_ui: true do
  HELP_PW = "demo-boulanger"
  HELP_SHOTS = Rails.root.join("tmp/shots")

  before do
    ENV["ADMIN_PASSWORD"] = HELP_PW
    FileUtils.mkdir_p(HELP_SHOTS)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: HELP_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  it "apparaît au sommaire, s'ouvre, et affiche ses captures" do
    sign_in_admin
    visit "/admin/aide"

    expect(page).to have_link("Régler les quantités et les recettes")
    click_link "Régler les quantités et les recettes"

    expect(page).to have_text("Quantité de pâte requise")
    expect(page).to have_text("fractions de la PÂTE")
    expect(page).to have_text("commande de test")

    # Les captures référencées se chargent vraiment (pas de placeholder).
    images = page.all("img").map { |img| img[:src] }
    expect(images.any? { |src| src.include?("product-variant-edit") }).to be true
    expect(images.any? { |src| src.include?("settings-flour-edit") }).to be true

    page.driver.browser.manage.window.resize_to(1500, 1050)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.5
    page.save_screenshot(HELP_SHOTS.join("aide-1-chapitre.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "garde la navigation entre chapitres" do
    sign_in_admin
    visit "/admin/aide/parametres"

    expect(page).to have_link("Régler les quantités et les recettes")
  end
end
