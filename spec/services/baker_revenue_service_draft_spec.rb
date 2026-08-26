require "rails_helper"

# #197 — un jour de cuisson en brouillon est une calculatrice de boulanger :
# il ne doit changer AUCUN chiffre. La démonstration est une comparaison stricte
# du rapport avec et sans le jour brouillon dans la période.
RSpec.describe BakerRevenueService, "jours de cuisson en brouillon" do
  # Le vendredi de LA MÊME semaine que le mardi : `next_occurring(:friday)`
  # pourrait tomber avant, et la période serait vide.
  let(:tuesday) { Date.current.next_occurring(:tuesday) }
  let(:friday)  { tuesday + 3.days }

  let(:variant) do
    product = create(:product, category: :breads, internal_category: :boulangerie)
    create(:product_variant, product: product, price_cents: 650).tap do |v|
      create(:variant_cost_price, product_variant: v, amount_cents: 200, active_from: Date.new(2026, 1, 1))
    end
  end

  let(:artisan) { create(:artisan, name: "Romane") }

  def completed_order(bake_day:, qty:)
    order = create(:order, :paid, bake_day: bake_day, total_cents: qty * variant.price_cents)
    create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: variant.price_cents)
    order
  end

  def report(start_date, end_date)
    described_class.new(start_date: start_date, end_date: end_date).call
  end

  let!(:real_day) { create(:bake_day, baked_on: tuesday) }

  before do
    create(:artisan_revenue_share, artisan: artisan, percent: 100, active_from: Date.new(2026, 1, 1))
    create(:bake_day_artisan, bake_day: real_day, artisan: artisan)
    completed_order(bake_day: real_day, qty: 10)
  end

  it "ne change aucun total quand un jour brouillon porte pourtant des commandes" do
    before_draft = report(tuesday, friday)

    draft_day = create(:bake_day, :draft, baked_on: friday)
    create(:bake_day_artisan, bake_day: draft_day, artisan: artisan)
    completed_order(bake_day: draft_day, qty: 40)

    after_draft = report(tuesday, friday)

    expect(after_draft.total_revenue_cents).to eq(before_draft.total_revenue_cents)
    expect(after_draft.gross_margin_cents).to eq(before_draft.gross_margin_cents)
    expect(after_draft.baker_pool_cents).to eq(before_draft.baker_pool_cents)
    expect(after_draft.four_sources_cents).to eq(before_draft.four_sources_cents)
    expect(after_draft.days.map(&:date)).to eq([ tuesday ])
  end

  it "réintègre le jour dès qu'on décoche le brouillon" do
    draft_day = create(:bake_day, :draft, baked_on: friday)
    create(:bake_day_artisan, bake_day: draft_day, artisan: artisan)
    completed_order(bake_day: draft_day, qty: 40)

    drafted = report(tuesday, friday)
    draft_day.update!(draft: false)
    undrafted = report(tuesday, friday)

    expect(drafted.days.map(&:date)).to eq([ tuesday ])
    expect(undrafted.days.map(&:date)).to eq([ tuesday, friday ])
    expect(undrafted.total_revenue_cents).to be > drafted.total_revenue_cents
  end

  it "exclut aussi le jour brouillon du reporting global" do
    draft_day = create(:bake_day, :draft, baked_on: friday)
    completed_order(bake_day: draft_day, qty: 40)

    expect(Order.revenue_between(tuesday, friday)).to eq(10 * variant.price_cents)
    expect(Order.completed.in_bake_day_range(tuesday, friday).distinct.count(:id)).to eq(1)
  end
end
