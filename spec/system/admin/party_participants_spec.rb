# frozen_string_literal: true

require "rails_helper"

# #206 — la liste nominative à l'écran, avec des données INVENTÉES.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — liste nominative d'une party historique", type: :system, browser_ui: true do
  PART_PW = "demo-boulanger"
  PART_SHOTS = Rails.root.join("tmp/shots")

  let(:date) { Date.new(2026, 7, 17) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:event) do
    create(:party_event, :public_party, held_on: date, title: "Pizza party du 17 juillet",
                                        historical_source: "billetweb",
                                        historical_adults: 35, historical_children: 16,
                                        historical_sourciers: 13, historical_fees_cents: 2_713)
  end

  before do
    ENV["ADMIN_PASSWORD"] = PART_PW
    FileUtils.mkdir_p(PART_SHOTS)

    # Noms INVENTÉS : le dépôt est public.
    [ [ "Dupuis", "Camille", "adult" ], [ "Dupuis", "Alex", "adult" ], [ "Dupuis", "Lou", "child" ],
      [ "Lemoine", "Sacha", "adult" ], [ "Lemoine", "Noa", "child" ] ].each_with_index do |(last, first, kind), i|
      create(:party_participant, party_event: event, last_name: last, first_name: first,
                                 ticket_kind: kind, email: "#{first.downcase}@example.test",
                                 external_reference: "CMD00#{(i / 3) + 1}",
                                 external_ticket_label: kind == "adult" ? "Place adulte" : "Place enfant",
                                 price_cents: kind == "adult" ? 1_000 : 600)
    end
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: PART_PW
    click_button "Se connecter"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  it "montre l'agrégat et la liste nominative, clairement séparés" do
    sign_in_admin
    visit "/admin/parties/#{event.id}"

    expect(page).to have_text("Ventes importées")
    expect(page).to have_text("Qui était là")
    expect(page).to have_text("Liste nominative — hors comptabilité")
    expect(page).to have_text("Camille")
    # `adm-eyebrow` met le texte en capitales via CSS : la comparaison ignore
    # donc la casse plutôt que de coder en dur le rendu.
    expect(page).to have_text(/5 participants · 3 adultes · 2 enfants/i)

    page.driver.browser.manage.window.resize_to(1500, 1150)
    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.4
    page.save_screenshot(PART_SHOTS.join("participants-fiche.png").to_s)
    page.driver.browser.manage.window.resize_to(1920, 1080)
  end
end
