require "rails_helper"

# Remboursement ligne à ligne depuis la fiche commande (#remboursement-partiel).
RSpec.describe "Admin::PartialRefunds", type: :request do
  around do |example|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    example.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def login_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, baked_on: Date.current) }
  let(:order) { create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 1_650) }
  let!(:item) { create(:order_item, order: order, qty: 3, unit_price_cents: 550) }
  let!(:wallet) { create(:wallet, customer: customer, balance_cents: 0) }

  before { order.update!(payment_status: :paid) }

  it "exige une authentification" do
    post partial_refund_admin_order_path(order), params: { channel: "wallet" }
    expect(response).to redirect_to(admin_login_path)
  end

  context "connecté" do
    before do
      login_admin
      allow(SmsService).to receive(:send_partial_refund)
    end

    it "affiche le formulaire sur la fiche d'une commande payée" do
      get admin_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Remboursement partiel")
      expect(response.body).to include(%(name="refund_items[#{item.id}]"))
    end

    it "rembourse les lignes cochées sur le portefeuille" do
      expect {
        post partial_refund_admin_order_path(order), params: {
          refund_items: { item.id.to_s => "1" },
          channel: "wallet",
          reason: "Pain manquant"
        }
      }.to change { wallet.reload.balance_cents }.by(550)

      expect(response).to redirect_to(admin_order_path(order))
      expect(order.reload.partially_refunded_cents).to eq(550)
      expect(order).to be_ready
    end

    it "accepte un montant forcé en euros" do
      post partial_refund_admin_order_path(order), params: {
        refund_items: { item.id.to_s => "1" },
        channel: "cash",
        amount_euros: "4,50"
      }

      expect(order.reload.partially_refunded_cents).to eq(450)
    end

    it "refuse et explique quand rien n'est coché" do
      expect {
        post partial_refund_admin_order_path(order), params: { channel: "wallet" }
      }.not_to change(PartialRefund, :count)

      follow_redirect!
      expect(response.body).to include("Sélectionne au moins un article")
    end

    it "clôt le signalement d'origine et le pré-remplit dans le formulaire" do
      issue = create(:order_issue, order: order, customer: customer)
      create(:order_issue_item, order_issue: issue, order_item: item, qty: 2)

      get admin_order_path(order)
      expect(response.body).to include("Problème signalé")

      post partial_refund_admin_order_path(order), params: {
        refund_items: { item.id.to_s => "2" },
        channel: "cash",
        order_issue_id: issue.id
      }

      expect(issue.reload).to be_state_resolved
    end

    it "permet de clore un signalement sans rembourser" do
      issue = create(:order_issue, order: order, customer: customer)

      patch resolve_admin_order_issue_path(issue)

      expect(issue.reload).to be_state_resolved
      expect(PartialRefund.count).to eq(0)
    end

    it "liste les signalements ouverts dans leur écran dédié" do
      issue = create(:order_issue, order: order, customer: customer, description: "Pain cru")

      get admin_order_issues_path

      expect(response.body).to include("Pain cru")
      expect(response.body).to include(order.order_number)

      issue.resolve!
      get admin_order_issues_path
      expect(response.body).not_to include("Pain cru")
    end
  end
end
