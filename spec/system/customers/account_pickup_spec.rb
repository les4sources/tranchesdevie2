# frozen_string_literal: true

require "rails_helper"

# Pointage « J'ai récupéré ma commande » sans rechargement (#291).
#
# Ce que seul un vrai navigateur peut prouver : que la page ne navigue PAS. On
# pose un marqueur sur `window` avant le clic — un rechargement l'effacerait.
RSpec.describe "Mon compte — pointer une commande récupérée", type: :system do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let(:customer) { create(:customer, first_name: "Alix", email: "alix@example.com") }

  # `csrf_meta_tags` ne rend RIEN quand la protection est désactivée (le défaut en
  # test), et le contrôleur Stimulus de connexion lit cette balise pour envoyer le
  # code : sans elle, la connexion échoue dans le navigateur alors qu'elle marche
  # en production. On rétablit donc la protection pour ces exemples.
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  before do
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })
  end

  def sign_in
    visit "/connexion"
    fill_in "identifier", with: customer.phone_e164
    click_button "Recevoir mon code"
    fill_in "otp_code", with: "123456"
    click_button "Vérifier le code"
    expect(page).to have_current_path(customers_account_path, wait: 10)
  end

  def ready_orders(count)
    friday = Date.current.next_occurring(:friday)
    Array.new(count) do |n|
      day = create(:bake_day, baked_on: friday + (n * 7))
      create(:order, :ready, customer: customer, bake_day: day, total_cents: 1_100)
    end
  end

  it "pointe deux commandes d'affilée sans jamais recharger la page" do
    orders = ready_orders(3)

    sign_in
    visit customers_account_path
    expect(page).to have_css("#order_row_#{orders.first.id}")

    click_button "Prêtes"
    expect(find("#acct-count-ready")).to have_text("3")

    page.execute_script("window.__noReload = true")

    within("#order_row_#{orders[0].id}") { click_button "J'ai récupéré ma commande" }
    expect(page).to have_text("Bon appétit !")
    expect(find("#acct-count-ready")).to have_text("2")
    expect(find("#acct-count-picked_up")).to have_text("1")
    # Onglet « Prêtes » actif : la ligne pointée sort de la vue sans rechargement.
    expect(page).to have_css("#order_row_#{orders[0].id}", visible: :hidden)
    expect(page.evaluate_script("window.__noReload")).to be true

    within("#order_row_#{orders[1].id}") { click_button "J'ai récupéré ma commande" }
    expect(find("#acct-count-ready")).to have_text("1")
    expect(find("#acct-count-picked_up")).to have_text("2")
    expect(page.evaluate_script("window.__noReload")).to be true

    # L'onglet « Prêtes » est resté actif tout du long.
    expect(find("[data-account-tab='ready']")[:class]).to include("is-active")
  end

  it "affiche la commande pointée comme « Récupérée » sous l'onglet Toutes" do
    orders = ready_orders(2)

    sign_in
    visit customers_account_path
    within("#order_row_#{orders[0].id}") { click_button "J'ai récupéré ma commande" }

    row = find("#order_row_#{orders[0].id}")
    expect(row).to have_text("Récupérée")
    expect(row[:"data-status"]).to eq("picked_up")
    expect(row).to have_no_button("J'ai récupéré ma commande")
    expect(row[:"data-order-modal-order-data-value"]).to include('"status":"picked_up"')
  end
end
