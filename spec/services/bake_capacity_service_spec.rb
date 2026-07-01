require 'rails_helper'

# Couvre l'invariant métier le plus critique de l'app : ne jamais accepter une
# commande qui dépasse la capacité physique d'un jour de cuisson (moules, pétrin,
# four). La logique vivait sans test ; ce fichier comble le trou.
RSpec.describe BakeCapacityService do
  # Limites larges par défaut ; chaque contexte resserre la ressource qu'il teste
  # via un override de `let` (les records ci-dessous les lisent à la construction).
  let(:oven_capacity_grams) { 100_000 }
  let(:mold_limit) { 100 }
  let(:kneader_limit_grams) { 100_000 }
  let(:flour_quantity) { 1_000 }

  let!(:production_setting) do
    ProductionSetting.create!(
      oven_capacity_grams: oven_capacity_grams,
      market_day_oven_capacity_grams: oven_capacity_grams * 2
    )
  end
  let!(:mold_type) { MoldType.create!(name: 'Moule test', limit: mold_limit, position: 1) }
  let!(:flour) { Flour.create!(name: 'Farine test', kneader_limit_grams: kneader_limit_grams, position: 1) }
  let!(:product) do
    create(:product, category: :breads).tap do |p|
      ProductFlour.create!(product: p, flour: flour, percentage: 100)
    end
  end
  let!(:variant) do
    create(:product_variant, product: product, flour_quantity: flour_quantity, mold_type: mold_type)
  end
  let(:bake_day) { create(:bake_day) }

  subject(:service) { described_class.new(bake_day) }

  # Panier au format session : tableau de hashes à clés string.
  def cart(qty, for_variant: variant)
    [ { 'product_variant_id' => for_variant.id, 'qty' => qty } ]
  end

  describe '#cart_fits?' do
    context 'when the bake day is empty and the cart is within every limit' do
      it 'fits with no errors' do
        result = service.cart_fits?(cart(2))
        expect(result[:fits]).to be true
        expect(result[:errors]).to be_empty
      end
    end

    context 'mold capacity (units per mold type)' do
      let(:mold_limit) { 5 }

      it 'rejects a cart that exceeds the mold unit limit' do
        result = service.cart_fits?(cart(6))
        expect(result[:fits]).to be false
        expect(result[:errors].join).to include('Moules')
      end

      it 'accepts a cart exactly at the mold limit (boundary is strictly greater-than)' do
        expect(service.cart_fits?(cart(5))[:fits]).to be true
      end
    end

    context 'kneader capacity (dough grams per flour)' do
      let(:kneader_limit_grams) { 5_000 } # 5 unités * 1000 g

      it 'rejects a cart whose dough exceeds a flour kneader limit' do
        result = service.cart_fits?(cart(6)) # 6000 g > 5000 g
        expect(result[:fits]).to be false
        expect(result[:errors].join).to include('Pétrin')
      end

      it 'accepts a cart exactly at the kneader limit' do
        expect(service.cart_fits?(cart(5))[:fits]).to be true # 5000 g == 5000 g
      end
    end

    context 'oven capacity (total dough grams)' do
      let(:oven_capacity_grams) { 5_000 }

      it 'rejects a cart whose total dough exceeds the oven capacity' do
        result = service.cart_fits?(cart(6)) # 6000 g > 5000 g
        expect(result[:fits]).to be false
        expect(result[:errors].join).to include('Four')
      end

      it 'accepts a cart exactly at the oven capacity' do
        expect(service.cart_fits?(cart(5))[:fits]).to be true # 5000 g == 5000 g
      end
    end

    context 'when existing non-cancelled orders already consume capacity' do
      let(:oven_capacity_grams) { 6_000 }

      before do
        order = create(:order, :paid, bake_day: bake_day)
        create(:order_item, order: order, product_variant: variant, qty: 4) # 4000 g déjà engagés
      end

      it 'counts the existing usage and rejects a cart that tips over' do
        result = service.cart_fits?(cart(3)) # 4000 + 3000 = 7000 g > 6000 g
        expect(result[:fits]).to be false
        expect(result[:errors].join).to include('Four')
      end

      it 'still accepts a cart that fits on top of existing usage' do
        expect(service.cart_fits?(cart(2))[:fits]).to be true # 4000 + 2000 = 6000 g
      end
    end

    context 'when re-checking capacity for an order being updated (#124)' do
      let(:oven_capacity_grams) { 6_000 }
      let!(:order_being_updated) do
        create(:order, :pending, bake_day: bake_day).tap do |o|
          create(:order_item, order: o, product_variant: variant, qty: 5) # 5000 g déjà réservés par elle-même
        end
      end

      it 'excludes the order own usage so a same-size update still fits' do
        # Sans exclusion : 5000 (soi-même) + 5000 (panier) = 10 000 > 6000 → rejet à tort.
        # Avec exclusion : 0 + 5000 = 5000 ≤ 6000 → accepté.
        result = service.cart_fits?(cart(5), exclude_order_id: order_being_updated.id)
        expect(result[:fits]).to be true
      end

      it 'still rejects a genuine over-reservation even when excluding the order' do
        result = service.cart_fits?(cart(7), exclude_order_id: order_being_updated.id) # 7000 > 6000
        expect(result[:fits]).to be false
        expect(result[:errors].join).to include('Four')
      end
    end

    context 'when an existing order on the bake day is cancelled (ISC-24)' do
      let(:oven_capacity_grams) { 6_000 }

      before do
        cancelled = create(:order, :cancelled, bake_day: bake_day)
        create(:order_item, order: cancelled, product_variant: variant, qty: 5) # 5000 g, mais annulés
      end

      it 'excludes cancelled orders from capacity usage' do
        # Si les annulées comptaient : 5000 + 3000 = 8000 > 6000 → rejet.
        # Comme elles sont exclues : 0 + 3000 = 3000 ≤ 6000 → accepté.
        expect(service.cart_fits?(cart(3))[:fits]).to be true
      end
    end

    context 'when the cart contains a non-bread product' do
      let(:oven_capacity_grams) { 1_000 }
      let!(:dough_ball_product) { create(:product, :dough_ball) }
      let!(:dough_ball_variant) do
        create(:product_variant, product: dough_ball_product, flour_quantity: flour_quantity, mold_type: mold_type)
      end

      it 'ignores it entirely (no mold/kneader/oven consumption)' do
        # 50 boules * 1000 g dépasseraient largement un four de 1000 g si comptées.
        result = service.cart_fits?(cart(50, for_variant: dough_ball_variant))
        expect(result[:fits]).to be true
      end
    end
  end

  describe '#usage with a multi-flour product' do
    let!(:flour_a) { Flour.create!(name: 'Froment', kneader_limit_grams: 100_000, position: 2) }
    let!(:flour_b) { Flour.create!(name: 'Seigle', kneader_limit_grams: 100_000, position: 3) }
    let!(:blend_product) do
      create(:product, category: :breads).tap do |p|
        ProductFlour.create!(product: p, flour: flour_a, percentage: 60)
        ProductFlour.create!(product: p, flour: flour_b, percentage: 40)
      end
    end
    let!(:blend_variant) { create(:product_variant, product: blend_product, flour_quantity: 1_000) }

    before do
      order = create(:order, :paid, bake_day: bake_day)
      create(:order_item, order: order, product_variant: blend_variant, qty: 10) # 10 000 g de pâte
    end

    it 'splits dough grams across flours by their percentage' do
      kneader = service.usage[:kneader]
      used_a = kneader.find { |e| e[:flour].id == flour_a.id }[:used]
      used_b = kneader.find { |e| e[:flour].id == flour_b.id }[:used]
      expect(used_a).to eq(6_000) # 60 % de 10 000 g
      expect(used_b).to eq(4_000) # 40 % de 10 000 g
    end
  end

  describe '#fully_booked? and #fill_percentage' do
    let(:oven_capacity_grams) { 6_000 }

    before do
      order = create(:order, :paid, bake_day: bake_day)
      create(:order_item, order: order, product_variant: variant, qty: 6) # 6000 g == capacité four
    end

    it 'reports 100% fill on the most constrained resource' do
      expect(service.fill_percentage).to eq(100)
    end

    it 'is fully booked at capacity' do
      expect(service.fully_booked?).to be true
    end
  end
end
