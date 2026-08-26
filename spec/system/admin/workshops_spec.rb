# frozen_string_literal: true

require "rails_helper"

# #208 — l'écran Ateliers et sa présence dans le rapport.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — ateliers", type: :system, browser_ui: true do
  WS_PW = "demo-boulanger"
  WS_SHOTS = Rails.root.join("tmp/shots")

  let!(:romane) { create(:artisan, name: "Romane") }
  let!(:stephanie) { create(:artisan, name: "Stéphanie") }

  before do
    ENV["ADMIN_PASSWORD"] = WS_PW
    FileUtils.mkdir_p(WS_SHOTS)
    create(:artisan_revenue_share, artisan: romane, percent: 50, active_from: Date.new(2026, 1, 1))
    create(:artisan_revenue_share, artisan: stephanie, percent: 50, active_from: Date.new(2026, 1, 1))
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: WS_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name, height)
    page.driver.browser.manage.window.resize_to(1500, height)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(WS_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "crée un atelier, l'affiche non réparti, puis réparti une fois le taux saisi" do
    sign_in_admin
    visit "/admin/ateliers"

    expect(page).to have_text("Répartition non définie")
    click_link "Nouvel atelier"

    fill_in "workshop[title]", with: "Atelier pain au levain"
    fill_in "workshop[held_on]", with: (Date.current + 7).strftime("%d/%m/%Y")
    fill_in "workshop[revenue_euros]", with: "300,00"
    fill_in "workshop[notes]", with: "Prévoir 12 tabliers."
    check "Romane"
    check "Stéphanie"
    capture("ateliers-1-formulaire", 1000)

    click_button "Créer l'atelier"
    expect(page).to have_text("Atelier créé.")
    expect(page).to have_text("Atelier pain au levain")
    expect(page).to have_text("Romane, Stéphanie")
    capture("ateliers-2-liste-sans-taux", 800)

    workshop = Workshop.last
    expect(workshop.revenue_cents).to eq(30_000)
    expect(workshop.artisans.count).to eq(2)

    # Une fois le taux saisi, la répartition s'applique.
    create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    visit "/admin/ateliers"
    expect(page).to have_no_text("Répartition non définie")
    expect(page).to have_text("30.0 % aux 4 Sources")
    capture("ateliers-3-liste-avec-taux", 800)
  end

  it "montre les ateliers dans le rapport des revenus, à part de la production" do
    create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:workshop, title: "Atelier pizza", held_on: Date.current - 3, revenue_cents: 20_000, artisans: [ romane ])
    create(:workshop, title: "Atelier à caler", held_on: Date.current - 5, revenue_cents: 15_000, artisans: [])

    sign_in_admin
    visit "/admin/reports/baker_revenue?start_date=#{Date.current - 30}&end_date=#{Date.current}"

    expect(page).to have_text("Ateliers (revenu complémentaire)")
    expect(page).to have_text("Atelier pizza")
    expect(page).to have_text("Aucun animateur")
    expect(page).to have_text("non réparti")

    page.driver.browser.manage.window.resize_to(1500, 1000)
    page.execute_script("document.querySelectorAll('section').forEach(s => { if (s.textContent.includes('Ateliers (revenu')) s.scrollIntoView({block: 'start'}) })")
    page.execute_script("window.scrollBy(0, -24)")
    sleep 0.4
    page.save_screenshot(WS_SHOTS.join("ateliers-4-rapport.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end
end
