require "rails_helper"

# #197 — le drapeau brouillon. Un brouillon disparaît de tout ce qui touche au
# client et à l'argent, et de rien d'autre : ses calculs internes marchent.
RSpec.describe BakeDay, "brouillon" do
  let(:tuesday) { Date.current.next_occurring(:tuesday) }

  it "n'est pas brouillon par défaut — les jours déjà en base restent comptabilisés" do
    expect(create(:bake_day, baked_on: tuesday).draft?).to be false
  end

  describe "scopes" do
    let!(:real_day)  { create(:bake_day, baked_on: tuesday) }
    let!(:draft_day) { create(:bake_day, :draft, baked_on: tuesday + 3.days) }

    it "sépare les jours comptabilisés des brouillons" do
      expect(described_class.accounted).to contain_exactly(real_day)
      expect(described_class.drafts).to contain_exactly(draft_day)
    end

    it "retire les brouillons de ce qui est visible par le client" do
      expect(described_class.visible_to_customers).to contain_exactly(real_day)
    end
  end

  describe "#visible_to_customers? / #open_to_customers?" do
    it "sont faux sur un brouillon, même un jour de cuisson valide et ouvert" do
      draft_day = create(:bake_day, :draft, :can_order, baked_on: tuesday)

      expect(draft_day.can_order?).to be true
      expect(draft_day.visible_to_customers?).to be false
      expect(draft_day.open_to_customers?).to be false
    end

    it "restent vrais sur un jour normal — aucune régression" do
      real_day = create(:bake_day, :can_order, baked_on: tuesday)

      expect(real_day.visible_to_customers?).to be true
      expect(real_day.open_to_customers?).to be true
    end
  end

  describe ".open_to_customers" do
    it "ne propose jamais un brouillon" do
      real_day = create(:bake_day, :can_order, baked_on: tuesday)
      create(:bake_day, :draft, :can_order, baked_on: tuesday + 3.days)

      expect(described_class.open_to_customers).to contain_exactly(real_day)
    end
  end

  describe "les calculs internes" do
    it "fonctionnent normalement sur un brouillon — c'est tout l'intérêt" do
      draft_day = create(:bake_day, :draft, baked_on: tuesday)
      flour = create(:flour, name: "Froment T65")
      product = create(:product, :bread, name: "Pain froment")
      create(:product_flour, product: product, flour: flour, percentage: 100)
      variant = create(:product_variant, product: product, flour_quantity: 800, price_cents: 650)

      order = create(:order, :paid, bake_day: draft_day, total_cents: 3_250)
      create(:order_item, order: order, product_variant: variant, qty: 5, unit_price_cents: 650)

      dashboard = Admin::BakeDayDashboard.new(draft_day)

      expect(dashboard.total_flour_quantity).to eq(4_000)
      expect(dashboard.dough_quantities[:totals][:pate_kg]).to eq(4.0)
      expect(BakeCapacityService.new(draft_day).usage[:oven][:used]).to eq(4_000)
    end
  end
end
