# frozen_string_literal: true

require "rails_helper"

# #210 — la DoD demande une capture du rendu MOBILE.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Numéro de la boulangerie", type: :system, browser_ui: true do
  PHONE_SHOTS = Rails.root.join("tmp/shots")

  let!(:default_pickup) { create(:pickup_location, :default) }

  before { FileUtils.mkdir_p(PHONE_SHOTS) }

  def capture(name, width, height)
    page.driver.browser.manage.window.resize_to(width, height)
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    sleep 0.5
    page.save_screenshot(PHONE_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "affiche le numéro cliquable dans le pied de page, sur mobile" do
    visit "/"

    expect(page).to have_text(BakeryDetails::PHONE_DISPLAY)
    link = find("a[href='tel:#{BakeryDetails::PHONE_E164}']", match: :first)
    expect(link.text).to include(BakeryDetails::PHONE_DISPLAY)

    capture("telephone-1-mobile", 390, 844)
  end

  it "l'affiche aussi sur desktop" do
    visit "/"

    expect(page).to have_css("a[href='tel:#{BakeryDetails::PHONE_E164}']")
    capture("telephone-2-desktop", 1400, 900)
  end

  it "l'affiche sur la page À propos" do
    visit "/a-propos"

    expect(page).to have_text(BakeryDetails::PHONE_DISPLAY)
    page.driver.browser.manage.window.resize_to(390, 844)
    page.execute_script("document.querySelector(\"a[href^='tel:']\").scrollIntoView({block: 'center'})")
    sleep 0.4
    page.save_screenshot(PHONE_SHOTS.join("telephone-3-a-propos.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end
end
