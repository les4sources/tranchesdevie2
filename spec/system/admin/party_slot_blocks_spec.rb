# frozen_string_literal: true

require "rails_helper"

# #200 — l'écran de blocage des créneaux, ouvert pour de vrai : c'est une 404
# qu'on corrige, la preuve doit être la page qui s'affiche.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — blocages de créneaux", type: :system, browser_ui: true do
  BLOCK_PW = "demo-boulanger"
  BLOCK_SHOTS = Rails.root.join("tmp/shots")

  before do
    ENV["ADMIN_PASSWORD"] = BLOCK_PW
    FileUtils.mkdir_p(BLOCK_SHOTS)
    PartySlotBlock.create!(blocked_on: Date.current + 7, slot: "soir", reason: "Fermeture annuelle")
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: BLOCK_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  it "s'ouvre sur /admin/parties/blocages au lieu de renvoyer une 404" do
    sign_in_admin
    visit "/admin/parties/blocages"

    expect(page).to have_no_text("The page you were looking for doesn't exist")
    expect(page).to have_text("Fermeture annuelle")

    page.driver.browser.manage.window.resize_to(1500, 850)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(BLOCK_SHOTS.join("blocages-ecran.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end
end
