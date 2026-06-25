require "rails_helper"

# Espace client : téléchargement de la facture PDF du détail d'une commande,
# réservé aux clients « facturables » (#38).
RSpec.describe "Customers::Invoices", type: :request do
  let(:product) { create(:product, name: "Pain froment") }
  let(:variant) { create(:product_variant, product: product, name: "Petit 600 g", price_cents: 550) }
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }

  def order_for(customer)
    create(:order, customer: customer, bake_day: bake_day, total_cents: 1100).tap do |o|
      create(:order_item, order: o, product_variant: variant, qty: 2, unit_price_cents: 550)
    end
  end

  # Reproduit le parcours de connexion OTP des specs existantes de l'espace client.
  def authenticate(customer)
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    post "/connexion", params: { identifier: customer.phone_e164 }
    post "/connexion", params: { identifier: customer.phone_e164, otp_code: "123456" }
  end

  context "client facturable connecté" do
    let(:customer) { create(:customer, billable: true) }
    let!(:order) { order_for(customer) }

    before { authenticate(customer) }

    it "peut télécharger le PDF de SA commande" do
      get customers_order_invoice_path(order_id: order.id)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.body).to start_with("%PDF")
    end

    it "ne peut PAS télécharger la facture d'un AUTRE client (404)" do
      other = create(:customer, billable: true)
      other_order = order_for(other)

      get customers_order_invoice_path(order_id: other_order.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  context "client NON facturable connecté" do
    let(:customer) { create(:customer, billable: false) }
    let!(:order) { order_for(customer) }

    before { authenticate(customer) }

    it "ne peut PAS télécharger de facture (404)" do
      get customers_order_invoice_path(order_id: order.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  context "client non connecté" do
    let(:customer) { create(:customer, billable: true) }
    let!(:order) { order_for(customer) }

    it "est redirigé vers la connexion" do
      get customers_order_invoice_path(order_id: order.id)

      expect(response).to redirect_to(customer_login_path)
    end
  end
end
