require "rails_helper"

# Alerte « Capacité four » (Claire, 28/09/2026) : à 130 kg de pain, choisir
# entre deux fournées pleines (140 kg) et une 3e fournée.
RSpec.describe OvenBatchAlert do
  let(:bake_day) { create(:bake_day) }

  def alert(kg, plan: nil)
    bake_day.oven_batch_plan = plan
    described_class.new(bake_day, kg * 1_000)
  end

  describe "#state" do
    it "reste silencieuse sous 130 kg" do
      expect(alert(129.9).state).to eq(:quiet)
    end

    it "demande une décision dès 130 kg" do
      expect(alert(130).state).to eq(:decision_needed)
      expect(alert(130)).to be_action_needed
      expect(alert(130).remaining_grams).to eq(10_000)
    end

    it "se tait une fois deux fournées pleines validées, tant que ça tient" do
      expect(alert(140, plan: 2).state).to eq(:two_batches)
      expect(alert(140, plan: 2)).not_to be_action_needed
    end

    it "revient quand deux fournées validées ne suffisent plus" do
      expect(alert(141, plan: 2).state).to eq(:over_two_batches)
      expect(alert(141, plan: 2)).to be_action_needed
      expect(alert(141, plan: 2)).not_to be_two_batches_possible
    end

    it "ne prévoit pas de 4e fournée une fois la 3e ouverte" do
      expect(alert(230, plan: 3).state).to eq(:third_batch)
      expect(alert(230, plan: 3)).not_to be_action_needed
    end
  end

  describe ".oven_grams_by_bake_day" do
    it "compte le pain des commandes non annulées, sans les pâtons" do
      bread = create(:product_variant, product: create(:product, :bread), flour_quantity: 1_000)
      paton = create(:product_variant, product: create(:product, :dough_ball), flour_quantity: 250)
      customer = create(:customer)

      live = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1_000)
      create(:order_item, order: live, product_variant: bread, qty: 3)
      create(:order_item, order: live, product_variant: paton, qty: 10)

      cancelled = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1_000)
      create(:order_item, order: cancelled, product_variant: bread, qty: 50)
      cancelled.update_columns(status: Order.statuses[:cancelled])

      expect(described_class.oven_grams_by_bake_day([ bake_day.id ])).to eq(bake_day.id => 3_000)
    end
  end
end
