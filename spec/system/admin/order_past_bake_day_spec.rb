# frozen_string_literal: true

require "rails_helper"

# #198 — le scénario complet de Romane, joué dans un navigateur : elle rentre
# du marché, la date est passée, elle encode la vente au bon client, et la
# feuille compta du jour bouge. Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — commande sur un jour de cuisson passé", type: :system, browser_ui: true do
  PAST_PW = "demo-boulanger"
  PAST_SHOTS = Rails.root.join("tmp/shots")

  let!(:past_day) { create(:bake_day, baked_on: Date.current.prev_occurring(:tuesday), cut_off_at: 10.days.ago) }
  let!(:kikrok) { create(:customer, last_name: "Kikrok", first_name: "Marché") }

  before do
    ENV["ADMIN_PASSWORD"] = PAST_PW
    FileUtils.mkdir_p(PAST_SHOTS)

    flour = create(:flour, name: "Froment T65")
    product = create(:product, :bread, name: "Pain froment", internal_category: :boulangerie)
    create(:product_flour, product: product, flour: flour, percentage: 100)
    @variant = create(:product_variant, product: product, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650)
    create(:variant_cost_price, product_variant: @variant, amount_cents: 200, active_from: Date.new(2026, 1, 1))
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: PAST_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name, height = 900)
    page.driver.browser.manage.window.resize_to(1500, height)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(PAST_SHOTS.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  it "encode une vente de marché sur un jour passé, avec avertissement, et la compta suit" do
    date = past_day.baked_on
    revenue_before = BakerRevenueService.new(start_date: date, end_date: date).call.total_revenue_cents

    sign_in_admin
    visit "/admin/orders/new"

    # L'avertissement n'apparaît PAS tant qu'aucun jour passé n'est choisi.
    expect(page).to have_no_text("Jour de cuisson passé — régularisation")
    capture("passe-1-formulaire")

    # Le sélecteur de client est remplacé par le widget `searchable-select` :
    # on écrit dans le `<select>` masqué, ce n'est pas lui qu'on teste ici.
    page.execute_script(<<~JS, kikrok.id.to_s)
      const select = document.querySelector('#order_customer_id')
      select.value = arguments[0]
      select.dispatchEvent(new Event('change', { bubbles: true }))
    JS

    find("#order_bake_day_id").find(:option, I18n.l(past_day.baked_on, format: "%A %d/%m/%Y").capitalize).select_option

    # Il apparaît dès le choix du jour, sans recharger la page.
    expect(page).to have_text("Jour de cuisson passé — régularisation")
    capture("passe-2-avertissement")

    fill_in "order[variant_quantities][#{@variant.id}]", with: "4"
    fill_in "order[final_total_euros]", with: "26,00"
    # Vente de marché déjà encaissée : c'est ce statut qui la fait entrer au CA.
    choose "Payée"
    click_button "Créer la commande"

    expect(page).to have_text("Commande créée", wait: 10)

    order = Order.last
    expect(order.bake_day).to eq(past_day)
    expect(order.customer).to eq(kikrok)
    expect(order.total_cents).to eq(2_600)

    revenue_after = BakerRevenueService.new(start_date: date, end_date: date).call.total_revenue_cents
    expect(revenue_after - revenue_before).to eq(2_600)

    visit "/admin/bake_days/#{past_day.id}/sheet"
    expect(page).to have_text("Pain froment")
    capture("passe-3-feuille-compta")
  end
end
