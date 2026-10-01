require "rails_helper"

# Pointage groupé depuis la fiche client : on coche les commandes que le client
# règle, le total dû s'affiche, un clic les pointe toutes (liquide / virement).
RSpec.describe "Admin — pointage groupé sur la fiche client", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:default_location) { create(:pickup_location, :default) }
  let(:bake_day) { create(:bake_day) }
  let(:customer) { create(:customer) }
  let(:variant) { create(:product_variant) }

  def order_for(owner = customer, status: :ready, total_cents: 1_500)
    order = create(:order, status: status, customer: owner, bake_day: bake_day, total_cents: total_cents)
    create(:order_item, order: order, product_variant: variant, qty: 1)
    order
  end

  def settle(ids, method)
    patch encaissement_admin_customer_path(customer), params: { order_ids: ids, method: method }
  end

  it "pointe toutes les commandes sélectionnées par virement ; une `unpaid` passe à `paid`" do
    first = order_for(total_cents: 1_500)
    second = order_for(status: :unpaid, total_cents: 2_250)

    settle([ first.id, second.id ], "transfer")

    expect(response).to redirect_to(admin_customer_path(customer))
    [ first, second ].each(&:reload)
    expect([ first, second ]).to all(satisfy { |o| o.offline_payment_transfer? && o.payment_status_paid? && o.paid_at.present? })
    expect(first.status).to eq("ready")
    expect(second.status).to eq("paid")
    expect(flash[:notice]).to include("2 commandes", "Virement", "37,50")
  end

  it "ne touche ni une commande payée en ligne, ni une commande d'un autre client, ni une planifiée" do
    online = order_for
    create(:payment, order: online)
    other = order_for(create(:customer))
    planned = order_for(status: :planned)
    due = order_for

    settle([ online.id, other.id, planned.id, due.id ], "cash")

    expect(online.reload.offline_payment_method).to be_nil
    expect(other.reload.offline_payment_method).to be_nil
    expect(planned.reload.offline_payment_method).to be_nil
    expect(due.reload.offline_payment_cash?).to be true
  end

  it "refuse un moyen inconnu et une sélection vide" do
    order = order_for

    settle([ order.id ], "bitcoin")
    expect(flash[:alert]).to eq("Moyen d'encaissement inconnu.")

    settle([], "cash")
    expect(flash[:alert]).to eq("Aucune commande à pointer dans la sélection.")
    expect(order.reload.offline_payment_method).to be_nil
  end

  it "affiche les cases à cocher, le total non payé et l'état de paiement" do
    order_for(total_cents: 1_000)
    order_for(total_cents: 2_500)
    paid_online = order_for
    create(:payment, order: paid_online)

    get admin_customer_path(customer)

    expect(response.body.scan('name="order_ids[]"').size).to eq(2)
    expect(response.body).to include("2 non payées")
    expect(response.body).to include("35,00")
    expect(response.body).to include("Payé · Carte / Bancontact")
    expect(response.body).to include("Marquer payé · Virement")
  end
end
