require 'rails_helper'

# Capacité des pâtons de Pizza party (#pizza-parties).
#
# Deux faits qu'aucune spec ne couvrait : les pâtons pèsent sur le PÉTRIN et la
# FARINE (jamais sur le four ni les moules), et une réservation validée mais non
# payée ne pèse sur rien du tout.
RSpec.describe "Capacité des pâtons de Pizza party" do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let(:flour) { create(:flour, name: "Froment T65", kneader_limit_grams: 10_000) }
  let(:bake_day) { create(:bake_day, baked_on: next_party_date) }

  let(:next_party_date) do
    (PartyRequest::MINIMUM_NOTICE_DAYS..(PartyRequest::MINIMUM_NOTICE_DAYS + 14))
      .map { |n| Date.current + n }
      .find { |date| PartyEvent::PRIVATE_WDAYS.include?(date.wday) }
  end

  let!(:party_product) do
    product = create(:product, :pizza_party)
    create(:product_flour, product: product, flour: flour, percentage: 100)
    product
  end
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200, flour_quantity: 250) }

  describe "BakeCapacityService#cart_fits?" do
    it "compte les pâtons dans le pétrin (avant, ils ne comptaient pour rien)" do
      result = BakeCapacityService.new(bake_day).cart_fits?(
        [ { "product_variant_id" => party_variant.id, "qty" => 20 } ]
      )

      expect(result[:fits]).to be true

      # 45 pâtons × 250 g = 11 250 g > limite de 10 kg du pétrin
      too_many = BakeCapacityService.new(bake_day).cart_fits?(
        [ { "product_variant_id" => party_variant.id, "qty" => 45 } ]
      )

      expect(too_many[:fits]).to be false
      expect(too_many[:errors].join).to match(/Pétrin/)
    end

    it "ne fait peser les pâtons ni sur le four ni sur les moules" do
      additional = BakeCapacityService.new(bake_day)
                                      .send(:compute_additional,
                                            [ { "product_variant_id" => party_variant.id, "qty" => 30 } ])

      expect(additional[:oven]).to eq(0)
      expect(additional[:molds]).to be_empty
      expect(additional[:kneader].values.sum).to eq(30 * 250)
    end
  end

  describe "une réservation validée mais non payée" do
    it "ne consomme aucune capacité (ni pétrin ni farine)" do
      event = create(:party_event, kind: :private_party, held_on: bake_day.baked_on, slot: :soir,
                                   title: nil, capacity: nil, registration_closes_at: nil)
      order = create(:order, customer: create(:customer, phone_e164: "+32470700700", email: "cap1@example.com"),
                             party_event: event, bake_day: nil, source: :party, status: :awaiting_payment)
      create(:order_item, order: order, product_variant: party_variant, qty: 30)

      usage = BakeCapacityService.new(bake_day).usage
      kneader_used = usage[:kneader].sum { |entry| entry[:used] }

      expect(kneader_used).to eq(0)
    end

    it "consomme la capacité une fois payée" do
      event = create(:party_event, kind: :private_party, held_on: bake_day.baked_on, slot: :soir,
                                   title: nil, capacity: nil, registration_closes_at: nil)
      order = create(:order, customer: create(:customer, phone_e164: "+32470700701", email: "cap2@example.com"),
                             party_event: event, bake_day: nil, source: :party, status: :paid)
      create(:order_item, order: order, product_variant: party_variant, qty: 30)

      usage = BakeCapacityService.new(bake_day).usage
      kneader_used = usage[:kneader].sum { |entry| entry[:used] }

      expect(kneader_used).to eq(30 * 250)
    end
  end

  describe "PartyEvent#preparation_missing?" do
    it "est faux quand la fournée du jour même prépare la party" do
      bake_day
      event = create(:party_event, kind: :private_party, held_on: bake_day.baked_on, slot: :soir,
                                   title: nil, capacity: nil, registration_closes_at: nil)

      expect(event.preparation_missing?).to be false
    end

    it "est vrai quand aucune fournée ne précède la party" do
      event = create(:party_event, kind: :private_party, held_on: Date.current + 60, slot: :soir,
                                   title: nil, capacity: nil, registration_closes_at: nil)

      expect(event.preparation_missing?).to be true
    end
  end
end
