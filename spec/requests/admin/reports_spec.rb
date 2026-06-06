require "rails_helper"

# Admin : reporting — commission Stripe par commande + CA net (#47).
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
  end
end
