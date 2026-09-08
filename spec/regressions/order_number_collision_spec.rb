require "rails_helper"

# Régression TRANCHESDEVIE-Z : deux `create_payment_intent` concurrents pour la même
# cliente. La requête 2 passe par PendingReservationReleaseService pendant que la
# requête 1 attend Stripe ; A ne doit plus être supprimée et B doit avoir son propre numéro.
RSpec.describe "Deux checkouts concurrents de la même cliente" do
  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:product) { create(:product, channel: "store") }
  let(:variant) { create(:product_variant, product: product, channel: "store", price_cents: 700) }
  let(:cart) { [ { "product_variant_id" => variant.id.to_s, "qty" => 1 } ] }

  def create_order
    OrderCreationService.new(
      customer: customer, bake_day: bake_day, cart_items: cart, payment_method: "online", skip_capacity_check: true
    ).call
  end

  it "laisse la commande de la requête 1 et donne un numéro distinct à la requête 2" do
    first = create_order
    expect(first.source).to eq("checkout")

    # Requête 2, pendant que la requête 1 attend Stripe :
    PendingReservationReleaseService.call(customer: customer, bake_day: bake_day)
    expect(Order.exists?(first.id)).to be(true)
    second = create_order
    expect(second.order_number).not_to eq(first.order_number)

    # Retour de Stripe dans la requête 1 :
    expect { first.update!(payment_intent_id: "pi_requete_1") }.not_to raise_error
  end
end
