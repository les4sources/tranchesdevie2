# frozen_string_literal: true

require "rails_helper"

# Alerte « Capacité four », pilotée pour de vrai dans un navigateur : le bandeau
# de l'admin, puis le choix des boulangers sur la fiche du jour, rendu par Turbo
# sans rechargement manuel.
#
# Exclu du run normal comme le calculateur (tag :batch_planner_ui) : il exige
# Chrome. Lancer avec : bundle exec rspec spec/system --tag batch_planner_ui
RSpec.describe "Admin — alerte capacité four", type: :system, batch_planner_ui: true do
  let(:admin_pw) { "demo-boulanger" }
  let(:shot_dir) { Rails.root.join("tmp/shots") }
  let(:bake_day) { create(:bake_day) }

  before do
    ENV["ADMIN_PASSWORD"] = admin_pw
    FileUtils.mkdir_p(shot_dir)

    variant = create(:product_variant, product: create(:product, :bread, name: "Pain froment"), flour_quantity: 1_000)
    order = create(:order, :paid, customer: create(:customer), bake_day: bake_day, total_cents: 1_000)
    create(:order_item, order: order, product_variant: variant, qty: 124)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: admin_pw
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  it "signale 120 kg partout, puis enregistre le choix sous les yeux" do
    sign_in_admin
    visit "/admin/bake_days"

    banner = find("[data-role='oven-batch-banner']")
    expect(banner).to have_text("124 kg de pain au four, deux fournées pleines ou une 3e fournée ?")
    page.save_screenshot(shot_dir.join("oven-alert-banner.png").to_s)

    banner.click
    expect(page).to have_text("Encore 6 kg et les deux fournées seront pleines.")
    page.save_screenshot(shot_dir.join("oven-alert-decision.png").to_s)

    click_button "Ouvrir une 3e fournée"
    expect(page).to have_text("3e fournée ouverte : l'horaire de production s'allonge.")
    expect(page).to have_text("horaire de production allongé (124 kg de pain au four à ce jour)")
    expect(page).to have_no_css("[data-role='oven-batch-banner']")
    page.save_screenshot(shot_dir.join("oven-alert-third.png").to_s)

    click_button "Revenir à 2 fournées"
    expect(page).to have_text("Deux fournées pleines validées : jusqu'à 130 kg de pain au four.")
    expect(bake_day.reload.oven_batch_plan).to eq(2)
  end
end
