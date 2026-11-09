require "rails_helper"

# Une commande saisie en admin, déjà débitée du portefeuille, puis modifiée :
# le portefeuille doit suivre le nouveau total (cas réel de novembre 2026, où
# deux commandes modifiées après débit ont faussé le solde d'une cliente).
RSpec.describe "Admin — modification d'une commande débitée du portefeuille", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:default_location) { create(:pickup_location, :default) }
  let(:bake_day) { create(:bake_day) }
  let(:customer) { create(:customer) }
  let!(:wallet) { create(:wallet, customer: customer, balance_cents: 10_000) }
  let(:variant) { create(:product_variant, price_cents: 500) }

  def debited_order(qty:)
    order = create(:order, :unpaid, customer: customer, bake_day: bake_day, total_cents: qty * 500, source: :admin)
    create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: 500)
    post charge_wallet_admin_order_path(order)
    order.reload
  end

  def edit_order(order, qty:)
    patch admin_order_path(order), params: {
      order: {
        customer_id: order.customer_id,
        bake_day_id: order.bake_day_id,
        status: order.status,
        final_total_euros: (qty * 500 / 100.0).to_s,
        variant_quantities: { variant.id => qty }
      }
    }
  end

  it "débite l'écart quand la commande grossit" do
    order = debited_order(qty: 2)
    expect(wallet.reload.balance_cents).to eq(9_000)

    edit_order(order, qty: 3)

    expect(response).to redirect_to(admin_order_path(order))
    expect(order.reload.total_cents).to eq(1_500)
    expect(wallet.reload.balance_cents).to eq(8_500)
    adjustment = wallet.wallet_transactions.order(:created_at).last
    expect(adjustment.transaction_type).to eq("order_adjustment")
    expect(adjustment.amount_cents).to eq(-500)
    expect(adjustment.order).to eq(order)
    expect(flash[:notice]).to include("5,00 € débité")
  end

  it "recrédite l'écart quand la commande diminue, sans la marquer remboursée" do
    order = debited_order(qty: 4)
    expect(wallet.reload.balance_cents).to eq(8_000)

    edit_order(order, qty: 1)

    expect(wallet.reload.balance_cents).to eq(9_500)
    expect(wallet.wallet_transactions.order(:created_at).last.amount_cents).to eq(1_500)
    order.reload
    expect(order.payment_status_paid?).to be true
    expect(order.payment_method).to eq(:wallet)
    expect(flash[:notice]).to include("15,00 € recrédité")
  end

  it "ne touche pas au portefeuille si le total ne change pas" do
    order = debited_order(qty: 2)

    expect { edit_order(order, qty: 2) }.not_to change(WalletTransaction, :count)
    expect(wallet.reload.balance_cents).to eq(9_000)
  end

  it "ne touche pas au portefeuille d'une commande payée autrement" do
    order = create(:order, :unpaid, customer: customer, bake_day: bake_day, total_cents: 1_000, source: :admin)
    create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 500)

    expect { edit_order(order, qty: 3) }.not_to change(WalletTransaction, :count)
    expect(wallet.reload.balance_cents).to eq(10_000)
  end

  it "suit plusieurs modifications successives" do
    order = debited_order(qty: 2)

    edit_order(order, qty: 5)
    edit_order(order.reload, qty: 1)

    # 100 − 10 (débit) − 15 (ajout) + 20 (retrait) = 95 € : exactement 100 − 5.
    expect(wallet.reload.balance_cents).to eq(9_500)
  end
end
