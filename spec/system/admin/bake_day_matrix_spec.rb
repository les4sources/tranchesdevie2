# frozen_string_literal: true

require "rails_helper"

# #196 — la preuve du bug de largeur ne peut venir que du navigateur : on mesure
# les colonnes rendues. Avant le correctif, la colonne « Classique 800 gr rond
# cuit sur pierre » faisait plusieurs fois la largeur des autres.
#
# Exclu du run normal (tag :browser_ui) parce qu'il exige Chrome.
RSpec.describe "Admin — matrice clients × variantes", type: :system, browser_ui: true do
  MATRIX_PW = "demo-boulanger"
  MATRIX_SHOTS = Rails.root.join("tmp/shots")

  let(:bake_day) { create(:bake_day) }

  before do
    ENV["ADMIN_PASSWORD"] = MATRIX_PW
    FileUtils.mkdir_p(MATRIX_SHOTS)

    flour = create(:flour, name: "Froment T65")
    product = create(:product, :bread, name: "Pain classique")
    create(:product_flour, product: product, flour: flour, percentage: 100)

    @variants = [
      "Classique 800 gr rond cuit sur pierre",
      "Petit 600 gr",
      "Grand 1 kg",
      "Demi 400 gr",
      "Moulé 800 gr"
    ].map { |name| create(:product_variant, product: product, name: name, flour_quantity: 800, price_cents: 650) }

    [ [ "Ancion", "Romane" ], [ "Bastin", "Thomas" ], [ "Colot", "Stéphanie" ] ].each do |last, first|
      customer = create(:customer, last_name: last, first_name: first)
      order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 3_250)
      @variants.each_with_index { |variant, i| create(:order_item, order: order, product_variant: variant, qty: i + 1, unit_price_cents: 650) }
    end
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: MATRIX_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  # Largeurs réellement rendues des cellules de quantité d'une ligne client.
  def variant_column_widths
    page.evaluate_script(<<~JS)
      Array.from(
        document.querySelector('[data-panel="clients"] table.adm-grid-matrix tbody tr td')
          .parentElement.querySelectorAll('td')
      ).slice(1, -1).map((td) => Math.round(td.getBoundingClientRect().width))
    JS
  end

  it "donne la même largeur à toutes les colonnes de variantes, nom long compris" do
    sign_in_admin
    visit "/admin/bake_days/#{bake_day.id}"
    click_button "Commandes par client"
    expect(page).to have_text("Classique 800 gr rond cuit sur pierre")

    widths = variant_column_widths

    expect(widths.size).to eq(5)
    # Toutes égales : l'écart entre la plus large et la plus étroite tient dans
    # l'arrondi au pixel.
    expect(widths.max - widths.min).to be <= 1

    # Et la matrice ne déborde pas de son conteneur défilant.
    overflow = page.evaluate_script(<<~JS)
      document.documentElement.scrollWidth - document.documentElement.clientWidth
    JS
    expect(overflow).to be <= 0
  end

  it "garde les colonnes figées et l'en-tête collant après le passage en layout fixe" do
    sign_in_admin
    visit "/admin/bake_days/#{bake_day.id}"
    click_button "Commandes par client"

    positions = page.evaluate_script(<<~JS)
      (function () {
        const table = document.querySelector('[data-panel="clients"] table.adm-grid-matrix')
        const first = table.querySelector('tbody tr td')
        const cells = first.parentElement.querySelectorAll('td')
        const last = cells[cells.length - 1]
        return {
          left: getComputedStyle(first).position,
          right: getComputedStyle(last).position,
          head: getComputedStyle(table.querySelector('thead')).position
        }
      })()
    JS

    expect(positions["left"]).to eq("sticky")
    expect(positions["right"]).to eq("sticky")
    expect(positions["head"]).to eq("sticky")

    page.driver.browser.manage.window.resize_to(1500, 900)
    page.execute_script("document.querySelector('[data-panel=\"clients\"] table.adm-grid-matrix').scrollIntoView({block: 'center'})")
    sleep 0.4
    page.save_screenshot(MATRIX_SHOTS.join("matrice-apres.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end
end
