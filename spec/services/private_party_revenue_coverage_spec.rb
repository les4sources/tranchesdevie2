require "rails_helper"

# #205 — vérification demandée par l'issue : CHAQUE commande de party privée
# finalisée d'une période contribue-t-elle à `BakerRevenueService` ?
#
# La réponse était NON pour les parties réservées EN LIGNE : elles sont créées
# avec `bake_day: nil` (`PartyOrderCreationService`), or
# `BakerRevenueService#day_party_orders` partait de `bake_day.orders`. C'est le
# bug « la pizza party du 4 septembre n'apparaît pas dans la feuille compta »
# (#207), corrigé depuis : le service ratisse aussi les commandes rattachées à
# un `PartyEvent` du jour, via `BakeDayPartyOrders`.
#
# Ces specs verrouillent la couverture des DEUX chemins — la party encodée en
# commande sur la fournée, et celle réservée en ligne — et nomment toute
# commande qui y échapperait à nouveau.
RSpec.describe "Couverture des parties privées dans les revenus boulangers" do
  let(:date) { Date.new(2026, 9, 4) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:customer) { create(:customer) }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: paton, amount_cents: 26, active_from: date - 30)
  end

  # Encodée en commande sur la fournée : le chemin historique.
  def party_on_bake_day(qty: 8)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: qty * 500)
    create(:order_item, order: order, product_variant: paton, qty: qty, unit_price_cents: 500)
    order
  end

  # Réservée en ligne : rattachée à un PartyEvent, SANS fournée.
  def party_on_event(qty: 8)
    event = create(:party_event, :private_party, held_on: date, slot: :soir)
    order = create(:order, :paid, customer: customer, bake_day: nil, party_event: event,
                                  source: :party, total_cents: qty * 500)
    create(:order_item, order: order, product_variant: paton, qty: qty, unit_price_cents: 500)
    order
  end

  def report
    BakerRevenueService.new(start_date: date, end_date: date).call
  end

  # Commandes de party privée finalisées de la période qui manquent aux revenus.
  # La référence est ce que le rapport COMPTE réellement : les commandes de la
  # fournée PLUS celles rattachées à un événement du jour (#207).
  def uncovered_orders
    counted_ids = (bake_day.orders.completed.pluck(:id) +
                   BakeDayPartyOrders.completed(bake_day).map(&:id)).to_set

    Admin::PrivatePartyIndex.new
      .entries
      .map(&:order)
      .select { |order| order.event_date == date && Order.completed.exists?(order.id) }
      .reject { |order| counted_ids.include?(order.id) }
  end

  it "compte une party encodée en commande sur la fournée" do
    party_on_bake_day(qty: 8)

    expect(report.total_party_persons).to eq(8)
    expect(uncovered_orders).to be_empty
  end

  it "NOMME toute party qui échapperait aux revenus, plutôt que de la taire" do
    party_on_event(qty: 8)

    missing = uncovered_orders

    expect(missing).to be_empty,
      "commandes de party privée absentes des revenus : #{missing.map(&:order_number).join(', ')}"
  end

  it "réservée en ligne, une party privée contribue aux revenus du jour" do
    party_on_event(qty: 8)

    expect(report.total_party_persons).to eq(8)
  end

  it "ne compte jamais deux fois une party qui a À LA FOIS un événement et une fournée" do
    event = create(:party_event, :private_party, held_on: date, slot: :soir)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, party_event: event,
                                  source: :party, total_cents: 8 * 500)
    create(:order_item, order: order, product_variant: paton, qty: 8, unit_price_cents: 500)

    expect(report.total_party_persons).to eq(8)
    expect(Admin::PrivatePartyIndex.new.entries.map(&:order).count(order)).to eq(1)
  end

  # L'issue est de VISIBILITÉ : aucun centime ne doit bouger.
  it "ne change pas d'un centime les revenus d'une période" do
    party_on_bake_day(qty: 8)

    before_values = report
    # Le nouvel écran ne fait que LIRE ; on le sollicite puis on recompare.
    Admin::PrivatePartyIndex.new.entries
    after_values = report

    expect(after_values.total_revenue_cents).to eq(before_values.total_revenue_cents)
    expect(after_values.baker_pool_cents).to eq(before_values.baker_pool_cents)
    expect(after_values.total_party_bakers_cents).to eq(before_values.total_party_bakers_cents)
    expect(after_values.total_party_four_sources_cents).to eq(before_values.total_party_four_sources_cents)
  end
end
