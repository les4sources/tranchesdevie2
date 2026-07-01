require "rails_helper"

# Parcours d'achat critique de bout en bout (#126) — fondation du harness system
# specs. Un client authentifié parcourt le catalogue, ajoute un produit, choisit
# un jour de cuisson, et « paie » (Stripe.js mocké côté client + Stripe stubé côté
# serveur) jusqu'à la page de confirmation. Aucun appel réseau réel vers Stripe.
RSpec.describe "Parcours checkout", type: :system do
  let!(:production_setting) do
    ProductionSetting.create!(oven_capacity_grams: 1_000_000, market_day_oven_capacity_grams: 2_000_000)
  end
  let!(:product) { create(:product, category: :breads, channel: "store", name: "Pain de campagne") }
  let!(:variant) do
    create(:product_variant, product: product, channel: "store", name: "800 g",
                             price_cents: 550, flour_quantity: 500)
  end
  let!(:bake_day) { create(:bake_day, :can_order) }
  let!(:customer) { create(:customer, phone_e164: "+32470112233", first_name: "Camille", last_name: "Dupont") }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
  end

  # Déroule le parcours complet et renvoie une fois sur la page de confirmation.
  def run_checkout_journey
    sign_in_customer(customer)
    stub_stripe_checkout(total_cents: 550)

    # Catalogue → fiche produit → ajout au panier (le JS renvoie vers /catalogue).
    visit root_path
    click_link "Pain de campagne"
    expect(page).to have_current_path(product_path(product))
    click_button "Ajouter dans mon panier"
    expect(page).to have_current_path(catalog_path, wait: 5)

    # Panier → choix du jour de cuisson (fetch AJAX qui pose session[:bake_day_id]).
    visit cart_path
    bake_day_radio = find("input[name='bake_day_id'][value='#{bake_day.id}']")
    bake_day_radio.click
    expect(bake_day_radio).to be_checked

    # On atteint réellement le checkout (preuve que la session porte bien le jour).
    click_link "Valider la commande"
    expect(page).to have_current_path(new_checkout_path, wait: 5)

    # Section paiement affichée (client connecté → OTP déjà validé) : on attend que
    # le PaymentIntent soit initialisé et le bouton activé, puis on « paie ».
    find("#submit-payment:not([disabled])", wait: 10).click
  end

  it "mène un client jusqu'à la page de confirmation avec une commande créée" do
    run_checkout_journey

    expect(page).to have_text("Commande confirmée", wait: 10)

    order = Order.find_by(customer: customer, bake_day: bake_day)
    expect(order).to be_present
    expect(order.order_items.sum(:qty)).to eq(1)
    # Le serveur a bien utilisé le stub Stripe (aucun appel réseau réel). Le JS de
    # /checkout réinitialise le paiement à chaque turbo:load, d'où plusieurs appels
    # possibles — on vérifie donc « au moins une fois ».
    expect(Stripe::PaymentIntent).to have_received(:create).at_least(:once)
  end

  it "fonctionne aussi en viewport mobile", mobile: true do
    run_checkout_journey

    expect(page).to have_text("Commande confirmée", wait: 10)
    expect(Order.find_by(customer: customer, bake_day: bake_day)).to be_present
  end
end
