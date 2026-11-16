require "rails_helper"

# Annuler une commande depuis sa fiche ET rendre l'argent dans le même geste
# (#annulation-portefeuille). Le cas réel : un froment 1 kg pour mardi, annulé
# après le cut-off, que Stéphanie ne parvenait pas à recréditer sur le
# portefeuille de la cliente.
RSpec.describe "Admin — annulation d'une commande avec remboursement", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
    allow(SmsService).to receive(:send_admin_cancellation_refund)
  end

  let!(:default_location) { create(:pickup_location, :default) }
  let(:bake_day) { create(:bake_day, :cut_off_passed) }
  let(:customer) { create(:customer) }
  let!(:wallet) { create(:wallet, customer: customer, balance_cents: 5_000) }
  let(:variant) { create(:product_variant) }

  def wallet_paid_order(status: :paid, total_cents: 650)
    order = create(:order, status, customer: customer, bake_day: bake_day, total_cents: total_cents, source: :calendar)
    create(:order_item, order: order, product_variant: variant, qty: 1)
    wallet.debit!(total_cents, type: :order_debit, order: order, description: "Commande #{order.order_number}")
    order.reload
  end

  it "annule et recrédite le portefeuille, même après le cut-off" do
    order = wallet_paid_order
    expect(wallet.reload.balance_cents).to eq(4_350)

    post cancel_admin_order_path(order), params: { refund: "wallet", notify: "1" }

    expect(response).to redirect_to(admin_order_path(order))
    expect(flash[:notice]).to eq("Commande annulée, 6,50 € recrédités sur le portefeuille")
    order.reload
    expect(order).to be_cancelled
    expect(order.payment_status).to eq("refunded")
    expect(wallet.reload.balance_cents).to eq(5_000)
    expect(wallet.wallet_transactions.last.transaction_type).to eq("order_refund")
    expect(SmsService).to have_received(:send_admin_cancellation_refund)
      .with(order, amount_cents: 650, channel: "wallet")
  end

  it "n'envoie pas de SMS quand la case est décochée" do
    order = wallet_paid_order

    post cancel_admin_order_path(order), params: { refund: "wallet", notify: "0" }

    expect(order.reload).to be_cancelled
    expect(SmsService).not_to have_received(:send_admin_cancellation_refund)
  end

  it "annule sans rembourser quand l'admin le choisit, puis permet de rembourser après coup" do
    order = wallet_paid_order

    post cancel_admin_order_path(order), params: { refund: "none" }
    expect(order.reload).to be_cancelled
    expect(wallet.reload.balance_cents).to eq(4_350)

    get admin_order_path(order)
    expect(response.body).to include("Commande annulée, mais pas encore remboursée.")
    expect(response.body).to include("Rembourser 6,50 €")

    post cancel_admin_order_path(order), params: { refund: "wallet" }
    expect(flash[:notice]).to eq("Remboursement effectué : 6,50 € recrédités sur le portefeuille")
    expect(wallet.reload.balance_cents).to eq(5_000)
    expect(order.reload.payment_status).to eq("refunded")
  end

  it "rattrape une commande annulée depuis « Modifier » sans remboursement" do
    order = wallet_paid_order
    order.update!(status: :cancelled) # ce que fait le formulaire « Modifier »

    get admin_order_path(order)
    expect(response.body).to include("Rembourser 6,50 €")

    post cancel_admin_order_path(order), params: { refund: "wallet" }
    expect(wallet.reload.balance_cents).to eq(5_000)

    # Une fois remboursée, plus rien à proposer — et pas de double crédit.
    get admin_order_path(order)
    expect(response.body).not_to include("pas encore remboursée")
    post cancel_admin_order_path(order), params: { refund: "wallet" }
    expect(flash[:alert]).to eq("Rien à rembourser sur cette commande.")
    expect(wallet.reload.balance_cents).to eq(5_000)
  end

  it "ne rend que le reste après un remboursement partiel" do
    order = wallet_paid_order(total_cents: 1_300)
    item = order.order_items.first
    PartialRefundService.new(order, lines: { item.id => 1 }, channel: "wallet", amount_cents: 300).call
    expect(wallet.reload.balance_cents).to eq(4_000)

    post cancel_admin_order_path(order), params: { refund: "wallet" }

    expect(wallet.reload.balance_cents).to eq(5_000)
    expect(order.reload.payment_status).to eq("refunded")
  end

  it "prévient, après une annulation depuis « Modifier », que l'argent n'est pas rendu" do
    order = wallet_paid_order

    patch admin_order_path(order), params: {
      order: {
        customer_id: customer.id, bake_day_id: bake_day.id, status: "cancelled",
        final_total_euros: "6,50", variant_quantities: { variant.id.to_s => "1" }
      }
    }

    expect(order.reload).to be_cancelled
    expect(flash[:alert]).to include("les 6,50 € payés n'ont pas encore été rendus")
  end

  it "rembourse sur la carte une commande payée par Stripe" do
    order = create(:order, :paid, :payment_paid, customer: customer, bake_day: bake_day, total_cents: 650)
    payment = create(:payment, order: order)
    allow(Stripe::Refund).to receive(:create).and_return(double(status: "succeeded", id: "re_1"))

    post cancel_admin_order_path(order), params: { refund: "stripe" }

    expect(Stripe::Refund).to have_received(:create).with({ payment_intent: payment.stripe_payment_intent_id, amount: 650 })
    expect(order.reload).to be_cancelled
    expect(payment.reload).to be_refunded
    expect(order.payment_status).to eq("refunded")
  end

  it "refuse le remboursement par carte d'une commande payée au portefeuille" do
    order = wallet_paid_order

    post cancel_admin_order_path(order), params: { refund: "stripe" }

    expect(flash[:alert]).to include("pas été payée par carte")
    expect(order.reload).to be_paid
  end

  it "annule simplement une commande non payée" do
    order = create(:order, :unpaid, customer: customer, bake_day: bake_day, source: :admin)

    get admin_order_path(order)
    expect(response.body).to include("Annuler la commande…")

    post cancel_admin_order_path(order), params: { refund: "none" }
    expect(order.reload).to be_cancelled
    expect(flash[:notice]).to eq("Commande annulée")
  end

  it "ne propose pas l'annulation d'une commande déjà retirée" do
    order = wallet_paid_order(status: :picked_up)

    get admin_order_path(order)
    expect(response.body).not_to include("Annuler la commande…")

    post cancel_admin_order_path(order), params: { refund: "wallet" }
    expect(flash[:alert]).to eq("Cette commande ne peut pas être annulée ici.")
    expect(order.reload).to be_picked_up
  end
end
