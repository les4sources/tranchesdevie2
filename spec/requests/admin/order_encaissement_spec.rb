require "rails_helper"

# Pointage de l'encaissement hors-ligne à la remise (#275).
#
# L'enjeu du geste : agir sur l'axe FINANCIER sans jamais toucher au `status`
# logistique — au moment de la remise la commande est déjà `ready`, et
# `ready → paid` n'est pas une transition autorisée.
RSpec.describe "Admin — pointage de l'encaissement", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:default_location) { create(:pickup_location, :default) }
  let(:bake_day) { create(:bake_day) }
  let(:customer) { create(:customer) }
  let(:variant) { create(:product_variant) }

  def ready_order
    order = create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 1_500)
    create(:order_item, order: order, product_variant: variant, qty: 2)
    order
  end

  def point(order, method)
    patch encaissement_admin_order_path(order, method: method)
    order.reload
  end

  describe "pointer un encaissement" do
    it "enregistre le liquide sans toucher au statut logistique" do
      order = ready_order

      point(order, "cash")

      expect(order.offline_payment_cash?).to be true
      expect(order.payment_status_paid?).to be true
      expect(order.paid_at).to be_present
      expect(order.status).to eq("ready")
      expect(order.payment_method).to eq(:cash)
    end

    it "enregistre le virement sans toucher au statut logistique" do
      order = ready_order

      point(order, "transfer")

      expect(order.offline_payment_transfer?).to be true
      expect(order.payment_status_paid?).to be true
      expect(order.status).to eq("ready")
      expect(order.payment_method).to eq(:transfer)
    end

    it "est idempotent : repointer ne décale pas la date du premier pointage" do
      order = ready_order
      point(order, "cash")
      first_paid_at = order.read_attribute(:paid_at)

      travel_to(2.hours.from_now) { point(order, "cash") }

      expect(order.read_attribute(:paid_at)).to eq(first_paid_at)
      expect(order.offline_payment_cash?).to be true
      expect(order.payment_status_paid?).to be true
    end

    it "permet de corriger un cash en virement" do
      order = ready_order
      point(order, "cash")

      point(order, "transfer")

      expect(order.offline_payment_transfer?).to be true
      expect(order.payment_status_paid?).to be true
    end

    it "rejette un moyen inconnu sans rien modifier" do
      order = ready_order

      point(order, "bitcoin")

      expect(order.offline_payment_method).to be_nil
      expect(order.payment_status_unpaid?).to be true
      expect(order.status).to eq("ready")
    end
  end

  describe "annuler un pointage (method=none)" do
    it "remet la commande à non pointée, paid_at compris" do
      order = ready_order
      point(order, "cash")

      point(order, "none")

      expect(order.offline_payment_method).to be_nil
      expect(order.payment_status_unpaid?).to be true
      expect(order.read_attribute(:paid_at)).to be_nil
      expect(order.status).to eq("ready")
      expect(order).to be_settlement_pending
    end
  end

  describe "commandes déjà payées pour de vrai" do
    it "refuse de pointer une commande réglée par Stripe" do
      order = ready_order
      create(:payment, order: order, status: :succeeded)

      point(order, "cash")

      expect(order.offline_payment_method).to be_nil
      expect(order.payment_method).to eq(:stripe)
      expect(order.status).to eq("ready")
    end

    it "refuse de pointer une commande débitée du portefeuille" do
      order = ready_order
      wallet = create(:wallet, customer: customer, balance_cents: 10_000)
      WalletService.debit_for_order(wallet: wallet, order: order)

      point(order, "cash")

      expect(order.reload.offline_payment_method).to be_nil
      expect(order.payment_method).to eq(:wallet)
    end
  end

  describe "la page du jour de cuisson" do
    it "affiche le montant non pointé et les deux boutons" do
      ready_order

      get admin_bake_day_path(bake_day)

      expect(response.body).to include("Encaissement non renseigné")
      expect(response.body).to include("n'est pas un impayé")
      expect(response.body).to include("Liquide", "Virement")
    end

    it "n'affiche pas les boutons pour une commande déjà payée en ligne" do
      order = ready_order
      create(:payment, order: order, status: :succeeded)

      get admin_bake_day_path(bake_day)

      expect(response.body).to include("Carte / Bancontact")
      expect(response.body).not_to include(encaissement_admin_order_path(order, method: "cash"))
    end
  end
end
