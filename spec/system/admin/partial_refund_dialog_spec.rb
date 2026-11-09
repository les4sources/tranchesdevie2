# frozen_string_literal: true

require "rails_helper"

# Le formulaire de remboursement partiel ne s'affiche plus en permanence sur la
# fiche commande : les boulangers croyaient qu'un remboursement avait eu lieu
# sur chaque commande. Il s'ouvre dans une modale, derrière un bouton.
# Exclu du run normal (tag :browser_ui).
RSpec.describe "Admin — remboursement partiel dans une modale", type: :system, browser_ui: true do
  DIALOG_PW = "demo-boulanger"
  DIALOG_SHOTS = Rails.root.join("tmp/shots")

  let(:customer) { create(:customer, first_name: "Romane", last_name: "Delvaux") }
  let(:bake_day) { create(:bake_day, baked_on: Date.current) }
  let(:order) { create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 1_650) }
  let!(:item) { create(:order_item, order: order, qty: 3, unit_price_cents: 550) }
  let!(:wallet) { create(:wallet, customer: customer, balance_cents: 0) }

  before do
    ENV["ADMIN_PASSWORD"] = DIALOG_PW
    FileUtils.mkdir_p(DIALOG_SHOTS)
    order.update!(payment_status: :paid)
    allow(SmsService).to receive(:send_partial_refund)
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: DIALOG_PW
    click_button "Entrer au fournil"
    expect(page).to have_no_current_path(%r{/admin/login}, wait: 10)
  end

  def capture(name)
    page.driver.browser.manage.window.resize_to(1500, 1000)
    sleep 0.4
    page.save_screenshot(DIALOG_SHOTS.join("#{name}.png").to_s)
  end

  it "cache le formulaire derrière un bouton et rembourse depuis la modale" do
    sign_in_admin
    visit "/admin/orders/#{order.id}"

    expect(page).to have_button("Rembourser une partie…")
    expect(page).to have_no_field("refund_items[#{item.id}]")
    capture("modale-1-fiche-commande")

    click_button "Rembourser une partie…"
    expect(page).to have_css("dialog#partial-refund-dialog[open]")
    find_field("refund_items[#{item.id}]").fill_in(with: "1")
    choose "channel", option: "wallet"
    capture("modale-2-formulaire-ouvert")

    # Annuler referme sans rien rembourser.
    within("dialog#partial-refund-dialog") { click_button "Annuler" }
    expect(page).to have_no_css("dialog#partial-refund-dialog[open]")
    expect(wallet.reload.balance_cents).to eq(0)

    click_button "Rembourser une partie…"
    find_field("refund_items[#{item.id}]").fill_in(with: "1")
    choose "channel", option: "wallet"
    accept_confirm { within("dialog#partial-refund-dialog") { click_button "Rembourser" } }

    expect(page).to have_text("Remboursement de 5,50 € enregistré")
    expect(wallet.reload.balance_cents).to eq(550)
  end

  it "ouvre la même modale depuis un signalement du client, quantités pré-remplies" do
    issue = create(:order_issue, order: order)
    create(:order_issue_item, order_issue: issue, order_item: item, qty: 2)

    sign_in_admin
    visit "/admin/orders/#{order.id}"
    click_button "Rembourser ce signalement…"

    expect(page).to have_css("dialog#partial-refund-dialog[open]")
    expect(find_field("refund_items[#{item.id}]").value).to eq("2")
    capture("modale-3-depuis-signalement")
  end
end
