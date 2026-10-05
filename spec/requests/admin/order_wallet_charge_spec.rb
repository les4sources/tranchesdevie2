require "rails_helper"

# Prélèvement sur le portefeuille d'une commande due saisie en admin : la
# cliente a un portefeuille chargé, le boulanger y prélève au lieu de laisser
# la commande « Non payée ».
RSpec.describe "Admin — prélèvement sur le portefeuille", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:default_location) { create(:pickup_location, :default) }
  let(:bake_day) { create(:bake_day) }
  let(:customer) { create(:customer) }
  let!(:wallet) { create(:wallet, customer: customer, balance_cents: 5_000) }
  let(:variant) { create(:product_variant) }

  def admin_order(status: :unpaid, total_cents: 1_500)
    order = create(:order, status, customer: customer, bake_day: bake_day, total_cents: total_cents, source: :admin)
    create(:order_item, order: order, product_variant: variant, qty: 2)
    order
  end

  it "débite le portefeuille et passe la commande non payée à payée" do
    order = admin_order

    post charge_wallet_admin_order_path(order)

    expect(response).to redirect_to(admin_order_path(order))
    order.reload
    expect(order.status).to eq("paid")
    expect(order.payment_status_paid?).to be true
    expect(order.payment_method).to eq(:wallet)
    expect(order.paid_at).to be_present
    expect(wallet.reload.balance_cents).to eq(3_500)
  end

  it "garde le statut logistique d'une commande déjà prête" do
    order = admin_order(status: :ready)

    post charge_wallet_admin_order_path(order)

    order.reload
    expect(order.status).to eq("ready")
    expect(order.payment_status_paid?).to be true
    expect(wallet.reload.balance_cents).to eq(3_500)
  end

  it "refuse quand le solde disponible est insuffisant" do
    order = admin_order(total_cents: 6_000)

    post charge_wallet_admin_order_path(order)

    expect(flash[:alert]).to eq("Solde du portefeuille insuffisant")
    expect(order.reload.status).to eq("unpaid")
    expect(wallet.reload.balance_cents).to eq(5_000)
  end

  it "ne dépense pas l'argent réservé aux commandes planifiées" do
    create(:order, :planned, customer: customer, bake_day: bake_day, total_cents: 4_000, source: :calendar)
    order = admin_order

    post charge_wallet_admin_order_path(order)

    expect(order.reload.status).to eq("unpaid")
    expect(wallet.reload.balance_cents).to eq(5_000)
  end

  it "ne prélève pas deux fois" do
    order = admin_order

    post charge_wallet_admin_order_path(order)
    post charge_wallet_admin_order_path(order)

    expect(wallet.reload.balance_cents).to eq(3_500)
    expect(flash[:alert]).to eq("Cette commande n'est pas à encaisser")
  end

  it "affiche le bouton sur la fiche d'une commande à encaisser" do
    order = admin_order

    get admin_order_path(order)

    expect(response.body).to include("Prélever sur le portefeuille")
  end
end
