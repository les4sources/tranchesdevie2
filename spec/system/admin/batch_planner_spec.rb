# frozen_string_literal: true

require "rails_helper"

# #194 — le calculateur de fournées, piloté pour de vrai dans un navigateur.
#
# Les specs de requête prouvent que le serveur fait le bon calcul ; celle-ci
# prouve la promesse faite aux boulangers : on coche, et les totaux bougent
# sous les yeux, sans rechargement ni bouton « Enregistrer ».
#
# Exclu du run normal (tag :batch_planner_ui) parce qu'il exige Chrome.
RSpec.describe "Admin — calculateur de fournées", type: :system, batch_planner_ui: true do
  ADMIN_PW = "demo-boulanger"
  SHOT_DIR = Rails.root.join("tmp/shots")

  let(:bake_day) { create(:bake_day) }

  before do
    ENV["ADMIN_PASSWORD"] = ADMIN_PW
    FileUtils.mkdir_p(SHOT_DIR)

    froment = create(:flour, name: "Froment T65", position: 1)
    seigle  = create(:flour, :seigle, name: "Seigle T130", position: 2)

    grand = create(:mold_type, name: "Grand moule", position: 1, limit: 80)
    petit = create(:mold_type, name: "Petit moule", position: 2, limit: 120)

    pain_froment = create(:product, :bread, name: "Pain froment")
    pain_seigle  = create(:product, :bread, name: "Pain seigle")
    create(:product_flour, product: pain_froment, flour: froment, percentage: 100)
    create(:product_flour, product: pain_seigle, flour: seigle, percentage: 100)

    @grand_froment = create(:product_variant, product: pain_froment, name: "Grand froment 800 gr", flour_quantity: 800, mold_type: grand, price_cents: 650)
    @petit_froment = create(:product_variant, product: pain_froment, name: "Petit froment 600 gr", flour_quantity: 600, mold_type: petit, price_cents: 500)
    @petit_seigle  = create(:product_variant, product: pain_seigle,  name: "Petit épeautre 600 gr", flour_quantity: 600, mold_type: petit, price_cents: 520)

    [ [ "Ancion", "Romane" ], [ "Bastin", "Thomas" ], [ "Colot", "Stéphanie" ] ].each_with_index do |(last, first), index|
      customer = create(:customer, last_name: last, first_name: first)
      order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 3_000)
      create(:order_item, order: order, product_variant: @grand_froment, qty: 3 + index, unit_price_cents: 650)
      create(:order_item, order: order, product_variant: @petit_froment, qty: 2 + index, unit_price_cents: 500)
      create(:order_item, order: order, product_variant: @petit_seigle,  qty: 1 + index, unit_price_cents: 520)
    end
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: ADMIN_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  # Cadre la capture sur le calculateur seul : on redimensionne la fenêtre à la
  # hauteur du panneau, puis on le ramène en haut de l'écran.
  def capture_planner(name)
    height = page.evaluate_script("document.querySelector('#batch-planner').getBoundingClientRect().height").to_i
    page.driver.browser.manage.window.resize_to(1600, [ [ height + 120, 900 ].max, 3000 ].min)
    page.execute_script("document.querySelector('#batch-planner').scrollIntoView({block: 'start'})")
    page.execute_script("window.scrollBy(0, -24)")
    sleep 0.4
    page.save_screenshot(SHOT_DIR.join("#{name}.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end

  def open_batches_tab
    visit "/admin/bake_days/#{bake_day.id}"
    click_button "Fournées"
    expect(page).to have_text("Calculateur de fournées")
  end

  # Le poids de pâte affiché sur la carte d'une fournée, en kg — lu dans le DOM,
  # pas recalculé : c'est bien ce que le boulanger voit qu'on vérifie.
  def displayed_dough_kg(batch)
    find("##{ActionView::RecordIdentifier.dom_id(batch)} [data-role='batch-dough']").text.to_s.tr(",", ".").to_f
  end

  it "crée deux fournées, répartit par client et par variante, et recalcule sous les yeux" do
    sign_in_admin
    open_batches_tab

    expect(page).to have_text("lignes non affectées")
    capture_planner("fournees-1-vide")

    click_button "Ajouter une fournée"
    expect(page).to have_field(with: "Fournée 1", wait: 10)
    click_button "Ajouter une fournée"
    expect(page).to have_field(with: "Fournée 2", wait: 10)

    # Affectation par client : les 3 lignes de Romane Ancion vers la fournée 1.
    romane_group = find("[role='group'][aria-label='Romane Ancion']")
    romane_group.all("button.adm-batchbtn")[0].click

    expect(page).to have_text("3 lignes → Fournée 1", wait: 10)

    first_batch, second_batch = bake_day.batches.ordered.to_a
    expect(displayed_dough_kg(first_batch)).to be > 0

    # Affectation par variante : tous les petits épeautres vers la fournée 2.
    epeautre_group = find("[role='group'][aria-label='Petit épeautre 600 gr']")
    epeautre_group.all("button.adm-batchbtn")[1].click
    expect(page).to have_text("→ Fournée 2", wait: 10)

    capture_planner("fournees-2-reparti")

    # Les totaux affichés correspondent au calcul serveur, sans rechargement.
    planner = Admin::BatchPlanner.new(bake_day.reload)
    expected = planner.batch_stats.map { |entry| (entry[:total_dough_grams] / 1000.0).round(2) }

    expect(displayed_dough_kg(first_batch)).to be_within(0.02).of(expected[0])
    expect(displayed_dough_kg(second_batch)).to be_within(0.02).of(expected[1])

    # La somme des fournées + le non-affecté retombe sur le tableau global.
    dashboard = Admin::BakeDayDashboard.new(bake_day)
    assigned = planner.batch_stats.sum { |entry| entry[:total_dough_grams] }
    unassigned = planner.unassigned_items.sum { |item| item.qty * item.product_variant.flour_quantity }
    expect(assigned + unassigned).to eq(dashboard.total_flour_quantity)
  end

  it "affiche les moules par type avec le détail de ce qui va dedans" do
    batch = create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1)
    OrderItem.joins(:order).where(orders: { bake_day_id: bake_day.id }).update_all(batch_id: batch.id)

    sign_in_admin
    open_batches_tab

    expect(page).to have_text("Grand moule")
    expect(page).to have_text("Petit moule")
    expect(page).to have_text("Grand froment 800 gr")
    expect(page).to have_text("Tout est réparti")

    capture_planner("fournees-3-moules")
  end
end
