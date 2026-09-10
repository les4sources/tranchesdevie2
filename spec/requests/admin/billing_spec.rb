require "rails_helper"

# Admin : vue de facturation mensuelle des clients professionnels (ISC-45).
RSpec.describe "Admin::Billing", type: :request do
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
    get admin_billing_path
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before { login_admin }

    let(:month) { Date.new(2026, 5, 1) }
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let!(:pro) { create(:customer, billable: true, first_name: "Épicerie", last_name: "Durand") }
    let!(:order) do
      create(:order, :unpaid, customer: pro, bake_day: bake_day, total_cents: 1500).tap do |o|
        create(:order_item, order: o, qty: 3)
      end
    end

    it "affiche le récapitulatif du mois pour les clients facturables" do
      get admin_billing_path(month: "2026-05")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Épicerie Durand")
      expect(response.body).to include("Impayé")
    end

    it "exporte le récapitulatif en CSV" do
      get admin_billing_path(month: "2026-05", format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Client")
      expect(response.body).to include("Épicerie Durand")
    end

    it "tolère un mois invalide en retombant sur le mois courant" do
      get admin_billing_path(month: "pas-une-date")
      expect(response).to have_http_status(:ok)
    end

    it "affiche le nom du produit en plus de la variante dans le détail (#98)" do
      product = create(:product, name: "Pain froment")
      variant = create(:product_variant, product: product, name: "Petit 600 g")
      detailed = create(:order, :unpaid, customer: pro, bake_day: bake_day, total_cents: 600)
      create(:order_item, order: detailed, product_variant: variant, qty: 1)

      get admin_billing_path(month: "2026-05")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pain froment — Petit 600 g")
    end

    it "inclut le nom du produit + variante dans l'export CSV (#98)" do
      product = create(:product, name: "Pain seigle")
      variant = create(:product_variant, product: product, name: "Grand 1 kg")
      detailed = create(:order, :unpaid, customer: pro, bake_day: bake_day, total_cents: 800)
      create(:order_item, order: detailed, product_variant: variant, qty: 2)

      get admin_billing_path(month: "2026-05", format: :csv)

      expect(response.body).to include("2x Pain seigle — Grand 1 kg")
    end

    # Marquage groupé depuis l'écran Facturation (#retour Manon) : Manon marque
    # « facturées » quand la facture part, « payées » quand l'argent arrive.
    describe "PATCH /admin/billing/commandes (marquage groupé)" do
      it "affiche une case à cocher par commande et le statut de facturation" do
        get admin_billing_path(month: "2026-05")

        expect(response.body).to include("name=\"order_ids[]\"")
        expect(response.body).to include("Non facturée")
        expect(response.body).to include("Marquer comme facturées")
        expect(response.body).to include("Marquer comme payées")
      end

      it "marque les commandes sélectionnées comme facturées" do
        patch admin_billing_bulk_update_path,
          params: { order_ids: [ order.id ], bulk_action: "mark_invoiced", month: "2026-05" }

        expect(order.reload.invoice_status).to eq("invoiced")
        expect(response).to redirect_to(admin_billing_path(month: "2026-05"))
        follow_redirect!
        expect(response.body).to include("Facturée")
      end

      it "revient sur « non facturée » quand on annule la facturation" do
        order.update!(invoice_status: :invoiced)

        patch admin_billing_bulk_update_path,
          params: { order_ids: [ order.id ], bulk_action: "mark_not_invoiced", month: "2026-05" }

        expect(order.reload.invoice_status).to eq("not_invoiced")
      end

      it "marque les commandes comme payées à la date saisie, sans toucher au statut logistique" do
        patch admin_billing_bulk_update_path,
          params: { order_ids: [ order.id ], bulk_action: "mark_paid", paid_at: "2026-06-03", month: "2026-05" }

        order.reload
        expect(order.payment_status).to eq("paid")
        expect(order.read_attribute(:paid_at)).to eq(Time.zone.local(2026, 6, 3))
        expect(order.status).to eq("unpaid")
      end

      it "conserve le filtre client dans la redirection" do
        patch admin_billing_bulk_update_path,
          params: { order_ids: [ order.id ], bulk_action: "mark_invoiced",
                    month: "2026-05", customer_id: pro.id }

        expect(response).to redirect_to(admin_billing_path(month: "2026-05", customer_id: pro.id.to_s))
      end

      it "refuse une commande dont le client n'est pas facturable" do
        particulier = create(:customer, billable: false)
        hors_perimetre = create(:order, :unpaid, customer: particulier, bake_day: bake_day, total_cents: 900)

        patch admin_billing_bulk_update_path,
          params: { order_ids: [ hors_perimetre.id ], bulk_action: "mark_invoiced", month: "2026-05" }

        expect(hors_perimetre.reload.invoice_status).to eq("not_invoiced")
        expect(flash[:alert]).to be_present
      end

      it "refuse une commande annulée, même chez un client facturable" do
        annulee = create(:order, :cancelled, customer: pro, bake_day: bake_day, total_cents: 900)

        patch admin_billing_bulk_update_path,
          params: { order_ids: [ annulee.id ], bulk_action: "mark_paid", month: "2026-05" }

        expect(annulee.reload.payment_status).to eq("unpaid")
      end

      it "signale une sélection vide sans rien modifier" do
        patch admin_billing_bulk_update_path, params: { bulk_action: "mark_invoiced", month: "2026-05" }

        expect(order.reload.invoice_status).to eq("not_invoiced")
        expect(flash[:alert]).to be_present
      end
    end
  end
end
