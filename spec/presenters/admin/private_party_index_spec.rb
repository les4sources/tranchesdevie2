require "rails_helper"

# #205 — retrouver les pizza parties privées dans l'écran Parties.
#
# Le constat de production du 25/08/2026 : 18 commandes de party privée
# finalisées, dont UNE seule portait un `PartyEvent`. L'écran partait des
# événements, le rapport part des commandes — ils ne voyaient pas le même monde.
RSpec.describe Admin::PrivatePartyIndex do
  let(:today) { Date.current }
  let!(:default_pickup) { create(:pickup_location, :default) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait") }
  let!(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store") }

  let(:customer) { create(:customer, first_name: "Fabienne", last_name: "Renard") }

  # Party « moderne » : réservée en ligne, rattachée à un PartyEvent, SANS fournée.
  def party_with_event(held_on:, qty: 8, with_forfait: true)
    event = create(:party_event, :private_party, held_on: held_on, slot: :soir)
    order = create(:order, :paid, customer: customer, bake_day: nil, party_event: event,
                                  source: :party, total_cents: qty * 500 + (with_forfait ? 4_000 : 0))
    create(:order_item, order: order, product_variant: paton, qty: qty, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait, qty: 1, unit_price_cents: 4_000) if with_forfait
    [ event, order ]
  end

  # Party « historique » : encodée directement en commande sur une fournée,
  # sans aucun PartyEvent — les 17 constatées en production.
  def party_without_event(baked_on:, qty: 8)
    bake_day = BakeDay.find_by(baked_on: baked_on) || create(:bake_day, baked_on: baked_on, cut_off_at: baked_on - 2.days)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: qty * 500)
    create(:order_item, order: order, product_variant: paton, qty: qty, unit_price_cents: 500)
    order
  end

  describe "#entries" do
    it "voit AUSSI les parties enregistrées sans événement" do
      _, with_event = party_with_event(held_on: today + 7)
      without_event = party_without_event(baked_on: today - 30)

      orders = described_class.new.entries.map(&:order)

      expect(orders).to include(with_event, without_event)
    end

    it "expose date, client, pâtons, montant et forfait" do
      _, order = party_with_event(held_on: today + 7, qty: 8, with_forfait: true)

      entry = described_class.new.entries.find { |e| e.order == order }

      expect(entry.held_on).to eq(today + 7)
      expect(entry.customer).to eq(customer)
      expect(entry.paton_count).to eq(8)
      expect(entry.total_cents).to eq(8 * 500 + 4_000)
      expect(entry.forfait?).to be true
      expect(entry.slot_label).to eq("Soir")
      expect(entry.event?).to be true
    end

    it "signale l'absence de forfait" do
      _, order = party_with_event(held_on: today + 7, with_forfait: false)

      expect(described_class.new.entries.find { |e| e.order == order }.forfait?).to be false
    end

    it "date une commande sans événement par sa fournée" do
      order = party_without_event(baked_on: today - 30)

      entry = described_class.new.entries.find { |e| e.order == order }

      expect(entry.held_on).to eq(today - 30)
      expect(entry.event?).to be false
      expect(entry.slot_label).to be_nil
    end

    it "exclut les commandes annulées" do
      _, order = party_with_event(held_on: today + 7)
      order.update!(status: :cancelled)

      expect(described_class.new.entries.map(&:order)).not_to include(order)
    end
  end

  describe "#upcoming / #past" do
    it "sépare l'avenir du passé — les passées ne disparaissent plus" do
      _, future = party_with_event(held_on: today + 7)
      old = party_without_event(baked_on: today - 30)

      index = described_class.new

      expect(index.upcoming.map(&:order)).to include(future)
      expect(index.upcoming.map(&:order)).not_to include(old)
      expect(index.past.map(&:order)).to include(old)
      expect(index.past.map(&:order)).not_to include(future)
    end

    # `Order` exige une fournée OU un événement (validation
    # `bake_day_or_party_event`) : une party sans date est donc impossible en
    # base. La liste sait tout de même l'afficher (« Sans date ») plutôt que de
    # la perdre, mais on vérifie surtout que le cas ne peut pas se produire.
    it "ne peut pas exister sans date : le modèle l'interdit" do
      order = build(:order, :paid, customer: customer, bake_day: nil, party_event: nil, total_cents: 4_000)

      expect(order).not_to be_valid
      expect(order.errors.full_messages.join).to match(/Bake day|fournée/i)
    end

    it "donne une date à toutes les entrées listées" do
      party_with_event(held_on: today + 7)
      party_without_event(baked_on: today - 30)

      expect(described_class.new.entries.map(&:held_on)).to all(be_present)
    end
  end

  # Le critère central de l'issue : mêmes parties, mêmes montants que le rapport.
  describe "cohérence avec le rapport pizza_parties" do
    it "liste exactement les mêmes commandes, pour les mêmes montants, sur la période" do
      start_date = today - 60
      end_date = today - 1

      3.times { |i| party_without_event(baked_on: today - (10 + i * 5)) }

      # La requête de référence du rapport (Admin::ReportsController).
      report_ids = OrderItem.joins(product_variant: :product)
                            .where(products: { pizza_party_role: Product.pizza_party_roles[:party] })
                            .select(:order_id)
      report_orders = Order.completed.in_bake_day_range(start_date, end_date).where(id: report_ids).to_a

      screen_orders = described_class.new.past
                                     .select { |e| e.held_on&.between?(start_date, end_date) }
                                     .map(&:order)

      expect(screen_orders.map(&:id).sort).to eq(report_orders.map(&:id).sort)
      expect(screen_orders.sum(&:total_cents)).to eq(report_orders.sum(&:total_cents))
    end
  end
end
