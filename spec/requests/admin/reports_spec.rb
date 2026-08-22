require "rails_helper"

# Admin : reporting des ventes — ventilation par catégorie interne (ISC-46)
# + commission Stripe par commande et CA net (#47).
RSpec.describe "Admin::Reports", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def login_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  it "exige une authentification" do
    get admin_reports_path
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before { login_admin }

    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:bakery_variant) do
      create(:product_variant, product: create(:product, internal_category: :boulangerie))
    end
    let(:grocery_variant) do
      create(:product_variant, product: create(:product, :epicerie))
    end

    it "affiche le CA net et le total des commissions Stripe" do
      order = create(:order, :paid, bake_day: bake_day, total_cents: 10_000)
      create(:payment, order: order, stripe_fee_cents: 250)

      get admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Commissions Stripe")
      expect(response.body).to include("CA net")
      # CA net = 10000 - 250 = 9750 cents → 97,50 €
      expect(response.body).to include("97,50")
      expect(response.body).to include("2,50")
    end

    it "affiche la section remboursements et déduit la commission Stripe non remboursée du CA net" do
      sale = create(:order, :paid, bake_day: bake_day, total_cents: 10_000)
      create(:payment, order: sale, stripe_fee_cents: 250)

      stripe_refund = create(:order, :cancelled, bake_day: bake_day, total_cents: 3_000)
      create(:payment, :refunded, order: stripe_refund, stripe_fee_cents: 90)

      wallet_order = create(:order, :cancelled, bake_day: bake_day, total_cents: 1_500)
      create(:wallet_transaction, :order_refund, order: wallet_order, amount_cents: 1_500)

      get admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Remboursements")
      # Montant total remboursé = 3000 + 1500 = 4500 cents → 45,00 €
      expect(response.body).to include("45,00")
      # CA net = 10000 - 250 (commission ventes) - 90 (commission remboursement) = 9660 → 96,60 €
      expect(response.body).to include("96,60")
    end

    it "affiche la ventilation des ventes par catégorie interne" do
      order = create(:order, :paid, bake_day: bake_day)
      create(:order_item, order: order, product_variant: bakery_variant, qty: 2, unit_price_cents: 500)
      create(:order_item, order: order, product_variant: grocery_variant, qty: 1, unit_price_cents: 300)

      get admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ventes par catégorie interne")
      expect(response.body).to include("Boulangerie")
      expect(response.body).to include("Épicerie")
    end

    it "fonctionne sans aucune vente sur la période" do
      get admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ventes par catégorie interne")
    end

    # #100 : drill-down détaillé des remboursements depuis le total.
    describe "GET /admin/reports/refunds" do
      let(:customer) { create(:customer, first_name: "Joséphine", last_name: "Martin") }

      it "liste les remboursements Stripe et portefeuille de la période avec montants" do
        stripe_order = create(:order, :cancelled, customer: customer, bake_day: bake_day, total_cents: 2000)
        create(:payment, :refunded, order: stripe_order, stripe_fee_cents: 60)

        wallet_order = create(:order, :cancelled, customer: customer, bake_day: bake_day, total_cents: 1500)
        create(:wallet_transaction, :order_refund, order: wallet_order, amount_cents: 1500)

        get refunds_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Détail des remboursements")
        expect(response.body).to include("Joséphine Martin")
        expect(response.body).to include(stripe_order.order_number)
        expect(response.body).to include(wallet_order.order_number)
        expect(response.body).to include("20,00") # 2000 cents Stripe
        expect(response.body).to include("15,00") # 1500 cents portefeuille
      end

      it "exclut les remboursements hors période" do
        out = create(:order, :cancelled, customer: customer,
                                          bake_day: create(:bake_day, baked_on: Date.new(2026, 4, 1)), total_cents: 9999)
        create(:payment, :refunded, order: out)

        get refunds_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(out.order_number)
        expect(response.body).to include("Aucun remboursement sur cette période.")
      end
    end
  end
end
