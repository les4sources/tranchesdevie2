# frozen_string_literal: true

require "rails_helper"

# #209 — l'historique des prix et le rapport de coût, à l'écran.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — prix au kilo historisés", type: :system, browser_ui: true do
  KP_PW = "demo-boulanger"
  KP_SHOTS = Rails.root.join("tmp/shots")

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:figues) { create(:ingredient, name: "Figues") }
  let!(:froment) { create(:flour, name: "Froment T65", price_per_kg_cents: nil) }

  before do
    ENV["ADMIN_PASSWORD"] = KP_PW
    FileUtils.mkdir_p(KP_SHOTS)

    product = create(:product, :bread, name: "Pain aux figues")
    create(:product_flour, product: product, flour: froment, percentage: 100)
    @variant = create(:product_variant, product: product, name: "Grand 1 kg", flour_quantity: 1_000, price_cents: 650)
    VariantIngredient.create!(product_variant: @variant, ingredient: figues, quantity: 50)

    create(:ingredient_price, ingredient: figues, amount_cents: 1_000, active_from: Date.current - 90)
    create(:ingredient_price, ingredient: figues, amount_cents: 1_400, active_from: Date.current - 10)
    create(:flour_price, flour: froment, amount_cents: 80, active_from: Date.current - 90)

    # Une vente il y a 30 jours : elle doit être valorisée à l'ANCIEN prix.
    date = Date.current - 30
    bake_day = create(:bake_day, baked_on: date, cut_off_at: date - 2.days)
    order = create(:order, :paid, customer: create(:customer), bake_day: bake_day, total_cents: 10 * 650)
    create(:order_item, order: order, product_variant: @variant, qty: 10, unit_price_cents: 650)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: KP_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name, height)
    page.driver.browser.manage.window.resize_to(1500, height)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(KP_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "montre l'historique des prix d'un ingrédient" do
    sign_in_admin
    visit "/admin/parametres/ingredients"
    click_link "Prix", match: :first

    expect(page).to have_text("Prix au kilo — Figues")
    expect(page).to have_text("En vigueur")
    expect(page).to have_text("Historique")
    capture("prix-1-historique", 700)
  end

  it "valorise le rapport de coût au prix de la fournée, pas au prix du jour" do
    sign_in_admin
    visit "/admin/reports/ingredient_costs?start_date=#{Date.current - 60}&end_date=#{Date.current}"

    expect(page).to have_text("Coût des matières premières")
    expect(page).to have_text("Figues")
    # 0,5 kg de figues au prix D'ALORS (10 €/kg) = 5,00 €, et non 7,00 €.
    expect(page).to have_text("5,00 €")
    expect(page).to have_no_text("7,00 €")
    capture("prix-2-rapport", 900)
  end

  it "ajoute un nouveau prix sans rien changer au passé" do
    before_cost = IngredientCostReportService.call(start_date: Date.current - 60, end_date: Date.current).total_cost_cents

    sign_in_admin
    visit "/admin/parametres/ingredients"
    click_link "Prix", match: :first
    click_link "Nouveau prix"

    fill_in "kilo_price[amount_euros]", with: "18,00"
    fill_in "kilo_price[active_from]", with: Date.current.strftime("%d/%m/%Y")
    capture("prix-3-formulaire", 620)
    click_button "Enregistrer"

    expect(page).to have_text("Prix enregistré.")

    after_cost = IngredientCostReportService.call(start_date: Date.current - 60, end_date: Date.current).total_cost_cents
    expect(after_cost).to eq(before_cost)
  end
end
