require "rails_helper"

RSpec.describe "Admin::BakeDays", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  # #71 : le planning du jour de cuisson contient la matrice « Commandes par client »
  # (produits en colonnes) dont l'en-tête doit rester figé au défilement. On vérifie
  # ici que la page rend sans erreur quand il y a au moins une commande (la matrice
  # est alors affichée), suite au passage du conteneur en scroll vertical.
  describe "GET /admin/bake_days/:id" do
    it "rend le planning avec la matrice commandes par client sans erreur" do
      bake_day = create(:bake_day)
      customer = create(:customer)
      product = create(:product, :bread)
      variant = create(:product_variant, product: product, price_cents: 550)
      order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1100)
      create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 550)

      get admin_bake_day_path(bake_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Commandes par client")
    end
  end

  # #133 : l'annulation d'une fournée passe par un écran de confirmation chiffré
  # + une garde délibérée (retaper la date). Aucune annulation possible sans elle.
  describe "confirmation renforcée avant annulation (#133)" do
    let(:bake_day) { create(:bake_day, :cut_off_passed) }
    let(:expected_date) { bake_day.baked_on.strftime("%d/%m/%Y") }

    before { allow(SmsService).to receive(:send_bake_cancelled).and_return(true) }

    def wallet_paid_order(total_cents: 1100)
      customer = create(:customer)
      wallet = create(:wallet, customer: customer, balance_cents: 0)
      order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: total_cents)
      create(:wallet_transaction, :order_debit, wallet: wallet, order: order)
      order
    end

    describe "GET /admin/bake_days/:id/confirm_cancel" do
      it "affiche l'impact chiffré de l'annulation" do
        wallet_paid_order(total_cents: 2000)

        get confirm_cancel_admin_bake_day_path(bake_day)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Impact de l'annulation")
        expect(response.body).to include("Portefeuille")
        expect(response.body).to include(expected_date)
      end
    end

    describe "POST /admin/bake_days/:id/cancel" do
      it "refuse d'annuler sans la garde saisie (aucun remboursement, aucun SMS)" do
        order = wallet_paid_order

        expect(SmsService).not_to receive(:send_bake_cancelled)
        post cancel_admin_bake_day_path(bake_day), params: { confirmation: "" }

        expect(response).to redirect_to(confirm_cancel_admin_bake_day_path(bake_day))
        expect(order.reload.status).to eq("paid")
        expect(order.customer.wallet.reload.balance_cents).to eq(0)
      end

      it "refuse d'annuler avec une garde erronée" do
        order = wallet_paid_order

        post cancel_admin_bake_day_path(bake_day), params: { confirmation: "31/12/1999" }

        expect(response).to redirect_to(confirm_cancel_admin_bake_day_path(bake_day))
        expect(order.reload.status).to eq("paid")
      end

      it "annule la fournée quand la date exacte est retapée" do
        order = wallet_paid_order

        expect(SmsService).to receive(:send_bake_cancelled).with(order, refunded: true)
        post cancel_admin_bake_day_path(bake_day), params: { confirmation: expected_date }

        expect(response).to redirect_to(admin_bake_day_path(bake_day))
        expect(order.reload.status).to eq("cancelled")
        expect(order.customer.wallet.reload.balance_cents).to eq(1100)
      end

      it "reste neutre s'il n'y a plus aucune commande annulable" do
        post cancel_admin_bake_day_path(bake_day), params: { confirmation: expected_date }

        expect(response).to redirect_to(admin_bake_day_path(bake_day))
        follow_redirect!
        expect(response.body).to include("Aucune commande à annuler")
      end
    end
  end
end
