require "rails_helper"

# Pizza parties privées enregistrées comme commandes de pain (ex. /admin/orders/627),
# converties en vraies parties sans toucher à la commande ni à la compta.
RSpec.describe LegacyPrivatePartyConversionService do
  let(:friday) { Date.new(2026, 7, 10) }
  let!(:bake_day) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, price_cents: 500, flour_quantity: 200) }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait") }
  let!(:forfait) { create(:product_variant, product: forfait_product, price_cents: 4_000) }
  let(:bread) { create(:product_variant, product: create(:product, :bread), price_cents: 450) }

  def legacy_order(persons: 12, with_forfait: true, extra: nil, **attrs)
    order = create(:order, bake_day: bake_day, source: :admin, status: :picked_up,
                           total_cents: persons * 500 + (with_forfait ? 4_000 : 0), **attrs)
    create(:order_item, order: order, product_variant: paton, qty: persons, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait, qty: 1, unit_price_cents: 4_000) if with_forfait
    create(:order_item, order: order, product_variant: extra, qty: 1, unit_price_cents: extra.price_cents) if extra
    order
  end

  describe "#candidates (simulation)" do
    it "propose la party du jour de fournée, au soir, sans rien écrire" do
      order = legacy_order(persons: 12)

      candidate = described_class.new.candidates.sole

      expect(candidate.order).to eq(order)
      expect(candidate).to be_convertible
      expect(candidate.held_on).to eq(friday)
      expect(candidate.slot).to eq("soir")
      expect(candidate.persons).to eq(12)
      expect(candidate.forfait).to be true
      expect(PartyEvent.count).to eq(0)
      expect(order.reload.party_event_id).to be_nil
    end

    it "écarte les commandes annulées et les commandes mixtes, avec la raison" do
      legacy_order(status: :cancelled)
      legacy_order(extra: bread)

      reasons = described_class.new.candidates.map(&:reason)

      expect(reasons).to contain_exactly("annulée", "mixte (pain + party) : à scinder à la main")
    end

    it "ignore les commandes de pain et les parties déjà rattachées" do
      plain = create(:order, bake_day: bake_day)
      create(:order_item, order: plain, product_variant: bread)
      event = PartyEvent.create!(kind: :private_party, held_on: friday, slot: "soir")
      legacy_order.update_columns(party_event_id: event.id, source: Order.sources[:party], bake_day_id: nil)

      expect(described_class.new.candidates).to be_empty
    end

    it "accepte une date et un créneau imposés pour une commande" do
      order = legacy_order
      saturday = friday + 1

      candidate = described_class.new(overrides: { order.id => { held_on: saturday, slot: "midi" } }).candidates.sole

      expect(candidate.held_on).to eq(saturday)
      expect(candidate.slot).to eq("midi")
    end
  end

  describe "#call" do
    it "rattache la commande à une party privée sans changer ni lignes, ni total, ni paiement" do
      order = legacy_order(persons: 12, payment_status: :paid, offline_payment_method: :cash)

      described_class.new.call
      order.reload

      event = order.party_event
      expect(event).to be_kind_private_party
      expect(event.held_on).to eq(friday)
      expect(event.slot).to eq("soir")
      expect(order).to be_private_party
      expect(order.source).to eq("party")
      expect(order.bake_day_id).to be_nil
      expect(order.total_cents).to eq(10_000)
      expect(order.order_items.sum(:qty)).to eq(13)
      expect(order.status).to eq("picked_up")
      expect(order).to be_payment_status_paid
      expect(order.offline_payment_method).to eq("cash")
      expect(order.party_paton_count).to eq(12)
    end

    it "ne déplace aucun euro : la fournée compte la party comme avant" do
      legacy_order(persons: 12)
      before = BakeDaySheetService.call(bake_day.reload).total_sale_cents

      described_class.new.call

      expect(BakeDaySheetService.call(bake_day.reload).total_sale_cents).to eq(before)
      expect(before).to eq(10_000)
    end

    it "est idempotente et laisse les commandes écartées intactes" do
      mixed = legacy_order(extra: bread)
      legacy_order

      described_class.new.call
      described_class.new.call

      expect(PartyEvent.count).to eq(1)
      expect(mixed.reload.party_event_id).to be_nil
      expect(mixed.bake_day_id).to eq(bake_day.id)
    end

    it "se limite aux commandes demandées" do
      first = legacy_order
      second = legacy_order

      described_class.new(order_ids: [ second.id ]).call

      expect(first.reload.party_event_id).to be_nil
      expect(second.reload.party_event_id).to be_present
    end
  end
end
