require "rails_helper"
require "pdf/reader"

# Admin : téléchargement des factures PDF (#38).
RSpec.describe "Admin::Invoices", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def login_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:customer) { create(:customer, billable: true, first_name: "Épicerie", last_name: "Durand") }
  let(:product) { create(:product, name: "Pain froment") }
  let(:variant) { create(:product_variant, product: product, name: "Petit 600 g", price_cents: 550) }
  let(:tuesday) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
  let(:friday) { create(:bake_day, baked_on: Date.new(2026, 5, 15)) }

  let!(:order_tue) do
    create(:order, customer: customer, bake_day: tuesday, total_cents: 1100).tap do |o|
      create(:order_item, order: o, product_variant: variant, qty: 2, unit_price_cents: 550)
    end
  end
  let!(:order_fri) do
    create(:order, customer: customer, bake_day: friday, total_cents: 550).tap do |o|
      create(:order_item, order: o, product_variant: variant, qty: 1, unit_price_cents: 550)
    end
  end

  it "exige une authentification admin" do
    get admin_order_invoice_path(order_id: order_tue.id)
    expect(response).to redirect_to(admin_login_path)
  end

  context "authentifié" do
    before { login_admin }

    describe "GET facture d'une commande" do
      it "renvoie un PDF non vide" do
        get admin_order_invoice_path(order_id: order_tue.id)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/pdf")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.body).to start_with("%PDF")
      end
    end

    describe "GET relevé de période (mensuel groupé)" do
      it "renvoie un relevé PDF groupé par jour de cuisson, sans mention fiscale" do
        get admin_period_invoice_path(customer_id: customer.id, month: "2026-05")

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/pdf")
        expect(response.body).to start_with("%PDF")

        text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
        expect(text).to include("Relevé de commandes")
        expect(text).not_to match(/facture/i)
        expect(text).to include(I18n.l(Date.new(2026, 5, 12)))
        expect(text).to include(I18n.l(Date.new(2026, 5, 15)))
      end

      it "redirige avec une alerte s'il n'y a aucune commande sur le mois" do
        empty = create(:customer, billable: true)
        get admin_period_invoice_path(customer_id: empty.id, month: "2026-05")

        expect(response).to redirect_to(admin_billing_path(month: "2026-05", customer_id: empty.id))
        follow_redirect!
        expect(response.body).to include("Aucune commande à facturer")
      end
    end
  end
end
