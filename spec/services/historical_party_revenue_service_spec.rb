require "rails_helper"

# Barème public rétroactif sur des ventes BilletWeb agrégées (#pizza-parties).
RSpec.describe HistoricalPartyRevenueService do
  let!(:product) { create(:product, :pizza_party_public, name: "Pizza Party publique") }
  let!(:adulte) { create(:product_variant, product: product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300) }
  let!(:enfant) { create(:product_variant, product: product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200) }

  # Juillet réel : 35 adultes, 16 enfants, frais BilletWeb 27,13 €. (Garnitures hors app.)
  let(:event) do
    create(:party_event, :public_party,
           title: "Pizza Party de juillet", held_on: Date.new(2026, 7, 18),
           historical_source: "billetweb", historical_adults: 35, historical_children: 16, historical_fees_cents: 2_713)
  end

  context "sans coûtant configuré (coûtant = 0)" do
    subject(:result) { described_class.call(event) }

    it "compte les participants" do
      expect(result.persons).to eq(51)
      expect(result.adults).to eq(35)
      expect(result.children).to eq(16)
    end

    it "calcule le CA des places (446 €)" do
      expect(result.sale_cents).to eq(44_600) # 35×1000 + 16×600
    end

    it "applique le barème : boulangers 216,30 € / 4S 229,70 €" do
      expect(result.bakers_cents).to eq(21_630)        # 35×490 + 16×280
      expect(result.four_sources_cents).to eq(22_970)  # 35×510 + 16×320
    end

    it "réconcilie : boulangers + 4S = CA − coûtant" do
      expect(result.bakers_cents + result.four_sources_cents).to eq(result.sale_cents - result.dough_cost_cents)
    end

    it "expose les frais et le net réellement encaissé par 4S" do
      expect(result.fees_cents).to eq(2_713)
      expect(result.net_to_four_sources_cents).to eq(41_887)        # 44600 − 2713
      expect(result.four_sources_effective_cents).to eq(20_257)     # 41887 − 21630 (dû aux boulangers)
    end
  end

  context "avec un coûtant configuré sur le pâton adulte" do
    before { create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: Date.new(2026, 1, 1)) }

    subject(:result) { described_class.call(event) }

    it "déduit le coûtant de la marge boulangers" do
      # adulte: marge 674 → boulangers 472 ; enfant inchangé 280
      expect(result.bakers_cents).to eq(35 * 472 + 16 * 280) # 16 520 + 4 480 = 21 000
      expect(result.dough_cost_cents).to eq(35 * 26)         # 910
    end
  end

  it "renvoie zéro pour un événement sans chiffres historiques" do
    blank = create(:party_event, :public_party, historical_source: nil)
    result = described_class.call(blank)
    expect(result.persons).to eq(0)
    expect(result.bakers_cents).to eq(0)
    expect(result.sale_cents).to eq(0)
  end
end
