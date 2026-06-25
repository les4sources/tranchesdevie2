require "rails_helper"

# Admin : reporting des versements Stripe (#49). Vérifie que la page rend,
# affiche brut / frais / net + le détail des commandes incluses, filtre par
# période, et gère une erreur Stripe SANS 500 (message propre).
RSpec.describe "Admin::Reports payouts", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def login_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  # Stub bas niveau du service : on isole la vue de l'API Stripe.
  def stub_report(report)
    allow(StripePayoutReportService).to receive(:new).and_return(
      instance_double(StripePayoutReportService, call: report)
    )
  end

  def payout_order(order)
    StripePayoutReportService::PayoutOrder.new(
      order: order,
      order_number: order.order_number,
      customer_name: order.customer.full_name,
      amount_cents: order.total_cents,
      fee_cents: 250
    )
  end

  def build_payout_row(stripe_id:, gross:, fee:, net:, orders: [], arrival_date: Date.new(2026, 5, 15))
    StripePayoutReportService::PayoutRow.new(
      stripe_id: stripe_id,
      arrival_date: arrival_date,
      status: "paid",
      gross_cents: gross,
      fee_cents: fee,
      net_cents: net,
      orders: orders.map { |o| payout_order(o) }
    )
  end

  def build_report(payouts:, error: nil)
    StripePayoutReportService::Report.new(
      start_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 5, 31),
      payouts: payouts,
      total_gross_cents: payouts.sum(&:gross_cents),
      total_fee_cents: payouts.sum(&:fee_cents),
      total_net_cents: payouts.sum(&:net_cents),
      error: error
    )
  end

  it "exige une authentification" do
    get payouts_admin_reports_path
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before { login_admin }

    it "rend la page avec brut / frais / net et le détail des commandes" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      order = create(:order, :paid, source: :checkout, bake_day: bake_day, total_cents: 10_000)

      report = build_report(payouts: [
        build_payout_row(stripe_id: "po_1", gross: 10_000, fee: 250, net: 9_750, orders: [ order ])
      ])
      stub_report(report)

      get payouts_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Versements Stripe")
      expect(response.body).to include("po_1")
      expect(response.body).to include("Brut").or include("brut")
      expect(response.body).to include("Frais").or include("frais")
      expect(response.body).to include("Net").or include("net")
      # Montants : brut 100,00 / frais 2,50 / net 97,50
      expect(response.body).to include("100,00")
      expect(response.body).to include("2,50")
      expect(response.body).to include("97,50")
      # Le détail des commandes incluses référence le numéro de commande.
      expect(response.body).to include(order.order_number)
    end

    it "affiche un message propre (pas de 500) quand Stripe échoue" do
      report = build_report(payouts: [], error: "Connexion à Stripe impossible")
      stub_report(report)

      get payouts_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stripe").and include("impossible").or include("indisponible")
    end

    it "passe les dates de la période filtrée au service" do
      expect(StripePayoutReportService).to receive(:new)
        .with(start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 31))
        .and_return(instance_double(StripePayoutReportService, call: build_report(payouts: [])))

      get payouts_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
    end

    it "affiche un état vide quand il n'y a aucun versement sur la période" do
      stub_report(build_report(payouts: []))

      get payouts_admin_reports_path(start_date: "2026-05-01", end_date: "2026-05-31")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aucun versement")
    end
  end
end
