require "rails_helper"

# Décompte séparé des variantes marquées (#151) dans le bloc « Moules ».
# Une variante « comptée séparément » et assignée à un moule reste comptée dans
# la capacité du moule, mais son nombre est exposé à part (`separate_tracking`).
RSpec.describe BakeCapacityService do
  let!(:production_setting) do
    ProductionSetting.create!(oven_capacity_grams: 100_000, market_day_oven_capacity_grams: 200_000)
  end
  let!(:grand) { MoldType.create!(name: "Grand", limit: 95, position: 1) }
  let(:product) { create(:product, category: :breads) }
  let(:bake_day) { create(:bake_day) }

  subject(:service) { described_class.new(bake_day) }

  def order_variant(variant, qty)
    order = create(:order, :paid, bake_day: bake_day)
    create(:order_item, order: order, product_variant: variant, qty: qty)
  end

  def grand_entry
    service.usage[:molds].find { |e| e[:mold_type].id == grand.id }
  end

  context "quand une variante marquée est assignée au moule" do
    let!(:xxl) do
      create(:product_variant, product: product, name: "XXL (1,4 kg)",
             mold_type: grand, track_capacity_separately: true)
    end
    let!(:standard) do
      create(:product_variant, product: product, name: "1 kg", mold_type: grand)
    end

    before do
      order_variant(xxl, 4)
      order_variant(standard, 6)
    end

    it "compte les XXL dans le total du moule Grand" do
      expect(grand_entry[:used]).to eq(10) # 4 XXL + 6 standard
    end

    it "expose le décompte des XXL à part" do
      breakdown = grand_entry[:separate_tracking]

      expect(breakdown.size).to eq(1)
      expect(breakdown.first[:variant]).to eq(xxl)
      expect(breakdown.first[:qty]).to eq(4)
    end
  end

  context "quand aucune variante n'est marquée" do
    let!(:standard) { create(:product_variant, product: product, name: "1 kg", mold_type: grand) }

    before { order_variant(standard, 6) }

    it "ne produit aucun décompte séparé (affichage inchangé)" do
      expect(grand_entry[:used]).to eq(6)
      expect(grand_entry[:separate_tracking]).to be_empty
    end
  end

  context "avec plusieurs variantes marquées sur le même moule" do
    let!(:xxl) do
      create(:product_variant, product: product, name: "XXL (1,4 kg)",
             mold_type: grand, track_capacity_separately: true)
    end
    let!(:special) do
      create(:product_variant, product: product, name: "Spécial fête",
             mold_type: grand, track_capacity_separately: true)
    end

    before do
      order_variant(xxl, 3)
      order_variant(special, 2)
    end

    it "liste chaque variante marquée séparément, triée par nom" do
      breakdown = grand_entry[:separate_tracking]

      expect(breakdown.map { |b| b[:variant] }).to eq([ special, xxl ])
      expect(breakdown.map { |b| b[:qty] }).to eq([ 2, 3 ])
      expect(grand_entry[:used]).to eq(5)
    end
  end
end
