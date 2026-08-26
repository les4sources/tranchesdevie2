require "rails_helper"

# #194 — le calculateur de fournées. Deux invariants tenus ici : la somme des
# fournées retombe sur le tableau global du jour quand tout est affecté, et une
# ligne non affectée reste comptée globalement sans entrer dans aucune fournée.
RSpec.describe Admin::BatchPlanner do
  let(:bake_day) { create(:bake_day) }
  let(:dashboard) { Admin::BakeDayDashboard.new(bake_day) }

  subject(:planner) { described_class.new(bake_day, dashboard) }

  let(:froment) { create(:flour, name: "Froment T65", position: 1, flour_ratio: 0.532, water_ratio: 0.391, salt_ratio: 0.012, levain_ratio: 0.120) }
  let(:seigle)  { create(:flour, :seigle, name: "Seigle", position: 2, flour_ratio: 0.500, water_ratio: 0.400, salt_ratio: 0.015, levain_ratio: 0.150) }

  let(:grand_moule) { create(:mold_type, name: "Grand moule", position: 1, limit: 100) }
  let(:petit_moule) { create(:mold_type, name: "Petit moule", position: 2, limit: 100) }

  let(:pain_froment) { create(:product, :bread, name: "Pain froment") }
  let(:pain_seigle)  { create(:product, :bread, name: "Pain seigle") }

  before do
    create(:product_flour, product: pain_froment, flour: froment, percentage: 100)
    create(:product_flour, product: pain_seigle, flour: seigle, percentage: 100)
  end

  let(:grand_froment) { create(:product_variant, product: pain_froment, name: "Grand froment 800 gr", flour_quantity: 800, mold_type: grand_moule) }
  let(:petit_froment) { create(:product_variant, product: pain_froment, name: "Petit froment 600 gr", flour_quantity: 600, mold_type: petit_moule) }
  let(:petit_seigle)  { create(:product_variant, product: pain_seigle,  name: "Petit seigle 600 gr",  flour_quantity: 600, mold_type: petit_moule) }

  let(:alice) { create(:customer, first_name: "Alice", last_name: "Aa") }
  let(:bob)   { create(:customer, first_name: "Bob",   last_name: "Bb") }

  let!(:alice_order) { create(:order, :paid, customer: alice, bake_day: bake_day, total_cents: 1000) }
  let!(:bob_order)   { create(:order, :paid, customer: bob,   bake_day: bake_day, total_cents: 1000) }

  let!(:alice_grand) { create(:order_item, order: alice_order, product_variant: grand_froment, qty: 5) }
  let!(:alice_petit) { create(:order_item, order: alice_order, product_variant: petit_seigle,  qty: 3) }
  let!(:bob_petit)   { create(:order_item, order: bob_order,   product_variant: petit_froment, qty: 4) }

  describe "sans fournée" do
    it "n'invente aucune répartition" do
      expect(planner.batches).to be_empty
      expect(planner.batch_stats).to be_empty
      expect(planner.unassigned_lines_count).to eq(3)
      expect(planner).not_to be_fully_assigned
    end
  end

  describe "avec deux fournées couvrant toutes les lignes" do
    let!(:first)  { create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1) }
    let!(:second) { create(:batch, bake_day: bake_day, name: "Fournée 2", position: 2) }

    before do
      alice_grand.update!(batch: first)
      bob_petit.update!(batch: first)
      alice_petit.update!(batch: second)
    end

    it "additionne exactement au tableau global du jour" do
      global = dashboard.dough_quantities[:totals]
      summed = planner.batch_stats.map { |entry| entry[:dough][:totals] }

      %i[pate_kg farine_kg sel_kg eau_l levain_kg].each do |key|
        expect(summed.sum { |totals| totals[key] }).to be_within(0.01).of(global[key]),
          "#{key} : #{summed.sum { |t| t[key] }} ≠ #{global[key]}"
      end
    end

    it "additionne exactement au poids de pâte global" do
      expect(planner.batch_stats.sum { |entry| entry[:total_dough_grams] })
        .to eq(dashboard.total_flour_quantity)
    end

    it "calcule la panification de chaque fournée avec les ratios de sa farine" do
      entry = planner.batch_stats.first
      # Fournée 1 : 5 × 800 g + 4 × 600 g = 6 400 g, tout en froment.
      expect(entry[:total_dough_grams]).to eq(6_400)
      expect(entry[:dough][:totals][:pate_kg]).to eq(6.4)
      expect(entry[:dough][:totals][:farine_kg]).to be_within(0.01).of(6.4 * 0.532)
      expect(entry[:dough][:totals][:eau_l]).to be_within(0.01).of(6.4 * 0.391)
      expect(entry[:dough][:totals][:sel_kg]).to be_within(0.001).of(6.4 * 0.012)
      expect(entry[:dough][:totals][:levain_kg]).to be_within(0.001).of(6.4 * 0.120)
    end

    it "sépare les deux totaux de levain par type" do
      expect(planner.batch_stats.first[:dough][:levain_by_type].keys).to eq([ "froment" ])
      expect(planner.batch_stats.second[:dough][:levain_by_type].keys).to eq([ "seigle" ])
    end

    it "compte les moules par type, avec le détail de ce qui va dedans" do
      molds = planner.batch_stats.first[:molds]

      grand = molds.find { |m| m[:mold_type] == grand_moule }
      petit = molds.find { |m| m[:mold_type] == petit_moule }

      expect(grand[:units_count]).to eq(5)
      expect(grand[:details]).to eq([ { variant: grand_froment, qty: 5 } ])
      expect(petit[:units_count]).to eq(4)
      expect(petit[:details]).to eq([ { variant: petit_froment, qty: 4 } ])
    end

    it "se recharge à l'identique" do
      expect(described_class.new(bake_day.reload).batch_stats.map { |e| e[:total_dough_grams] })
        .to eq([ 6_400, 1_800 ])
    end

    it "signale que tout est réparti" do
      expect(planner).to be_fully_assigned
      expect(planner.unassigned_lines_count).to eq(0)
    end
  end

  describe "avec une ligne laissée non affectée" do
    let!(:only_batch) { create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1) }

    before do
      alice_grand.update!(batch: only_batch)
      bob_petit.update!(batch: only_batch)
      # alice_petit reste non affectée.
    end

    it "l'exclut des fournées mais la garde dans le total global" do
      expect(planner.batch_stats.sum { |entry| entry[:total_dough_grams] }).to eq(6_400)
      expect(dashboard.total_flour_quantity).to eq(6_400 + 1_800)
    end

    it "la rend visible et dénombrable" do
      expect(planner.unassigned_lines_count).to eq(1)
      expect(planner.unassigned_units_count).to eq(3)
      expect(planner).not_to be_fully_assigned
    end
  end

  describe "#customer_rows" do
    let!(:batch) { create(:batch, bake_day: bake_day, position: 1) }

    it "groupe les lignes par client et n'allume la fournée que si TOUTES y sont" do
      alice_grand.update!(batch: batch)
      row = planner.customer_rows.find { |r| r[:customer] == alice }

      expect(row[:lines].size).to eq(2)
      # Panaché : une ligne dedans, une dehors — aucun bouton ne doit s'allumer.
      expect(row[:uniform_batch_id]).to eq(:mixed)

      alice_petit.update!(batch: batch)
      expect(described_class.new(bake_day.reload)
        .customer_rows.find { |r| r[:customer] == alice }[:uniform_batch_id]).to eq(batch.id)
    end
  end

  describe "#uniform_batch_id" do
    let!(:batch) { create(:batch, bake_day: bake_day, position: 1) }

    it "distingue « rien d'affecté » de « panaché »" do
      row = planner.customer_rows.find { |r| r[:customer] == bob }
      expect(row[:uniform_batch_id]).to be_nil

      bob_petit.update!(batch: batch)
      expect(described_class.new(bake_day.reload)
        .customer_rows.find { |r| r[:customer] == bob }[:uniform_batch_id]).to eq(batch.id)
    end
  end

  describe "#variant_rows" do
    it "agrège les lignes d'une même variante entre clients" do
      other_order = create(:order, :paid, customer: bob, bake_day: bake_day, total_cents: 500)
      create(:order_item, order: other_order, product_variant: grand_froment, qty: 2)

      row = described_class.new(bake_day.reload).variant_rows.find { |r| r[:variant] == grand_froment }

      expect(row[:lines_count]).to eq(2)
      expect(row[:units_count]).to eq(7)
      expect(row[:unassigned_units]).to eq(7)
    end
  end
end
