require "rails_helper"

# #208 — les ateliers dans le rapport « Revenus des boulangers ».
#
# Deux exigences fortes : les revenus de PRODUCTION ne bougent pas d'un centime,
# et la part atelier traverse le MÊME mécanisme de partenariat que la production
# (Romane / Stéphanie 50/50, y compris quand l'une est absente).
RSpec.describe BakerRevenueService, "ateliers" do
  let(:start_date) { Date.new(2026, 9, 1) }
  let(:end_date) { Date.new(2026, 9, 30) }
  let(:bake_date) { Date.new(2026, 9, 4) }
  let(:workshop_date) { Date.new(2026, 9, 10) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: bake_date, cut_off_at: bake_date - 2.days) }

  let(:romane) { create(:artisan, name: "Romane") }
  let(:stephanie) { create(:artisan, name: "Stéphanie") }

  let(:bread) { create(:product, :bread, name: "Pain froment") }
  let!(:variant) { create(:product_variant, product: bread, name: "Grand", flour_quantity: 800, price_cents: 650) }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: variant, amount_cents: 200, active_from: Date.new(2026, 1, 1))
    create(:artisan_revenue_share, artisan: romane, percent: 50, active_from: Date.new(2026, 1, 1))
    create(:artisan_revenue_share, artisan: stephanie, percent: 50, active_from: Date.new(2026, 1, 1))

    # Une vraie journée de production, animée par les deux.
    create(:bake_day_artisan, bake_day: bake_day, artisan: romane)
    create(:bake_day_artisan, bake_day: bake_day, artisan: stephanie)
    order = create(:order, :paid, customer: create(:customer), bake_day: bake_day, total_cents: 20 * 650)
    create(:order_item, order: order, product_variant: variant, qty: 20, unit_price_cents: 650)
  end

  def report
    described_class.new(start_date: start_date, end_date: end_date).call
  end

  describe "non-régression de la production" do
    it "sans atelier, les chiffres sont ceux d'avant la fonctionnalité" do
      result = report

      expect(result.total_revenue_cents).to eq(13_000)
      expect(result.workshops).to be_empty
      expect(result.total_workshop_revenue_cents).to eq(0)
      expect(result.total_workshop_bakers_cents).to eq(0)
      expect(result.workshops_undistributed_count).to eq(0)
    end

    it "avec un atelier, les chiffres de PRODUCTION restent identiques au centime" do
      create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1))

      before_workshop = report
      production_pool = before_workshop.baker_pool_cents
      production_4s = before_workshop.four_sources_cents
      production_revenue = before_workshop.total_revenue_cents

      create(:workshop, held_on: workshop_date, revenue_cents: 30_000, artisans: [ romane, stephanie ])

      after_workshop = report

      # Le CA de production, les jours et leurs marges : intacts.
      expect(after_workshop.total_revenue_cents).to eq(production_revenue)
      expect(after_workshop.days.sum(&:baker_pool_cents)).to eq(before_workshop.days.sum(&:baker_pool_cents))
      expect(after_workshop.days.sum(&:four_sources_cents)).to eq(before_workshop.days.sum(&:four_sources_cents))

      # Et l'atelier s'AJOUTE, sans se mélanger.
      expect(after_workshop.baker_pool_cents - production_pool).to eq(21_000)
      expect(after_workshop.four_sources_cents - production_4s).to eq(9_000)
    end

    it "un atelier non réparti n'ajoute rien du tout" do
      before_workshop = report
      create(:workshop, held_on: workshop_date, revenue_cents: 30_000, artisans: [ romane ])
      after_workshop = report

      expect(after_workshop.baker_pool_cents).to eq(before_workshop.baker_pool_cents)
      expect(after_workshop.four_sources_cents).to eq(before_workshop.four_sources_cents)
      expect(after_workshop.total_workshop_revenue_cents).to eq(30_000)
      expect(after_workshop.workshops_undistributed_count).to eq(1)
    end
  end

  describe "identification séparée" do
    before { create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1)) }

    it "expose les ateliers de la période, distincts de la production" do
      create(:workshop, held_on: workshop_date, title: "Atelier pizza", revenue_cents: 20_000, artisans: [ romane ])

      result = report

      expect(result.workshops.size).to eq(1)
      expect(result.workshops.first.workshop.title).to eq("Atelier pizza")
      expect(result.total_workshop_revenue_cents).to eq(20_000)
      expect(result.total_workshop_four_sources_cents).to eq(6_000)
      expect(result.total_workshop_bakers_cents).to eq(14_000)
    end

    it "ignore un atelier hors de la période" do
      create(:workshop, held_on: Date.new(2026, 8, 15), revenue_cents: 20_000, artisans: [ romane ])

      expect(report.workshops).to be_empty
    end
  end

  # Le mécanisme de groupe, réutilisé et non réinventé.
  describe "la couche partenariat s'applique aux ateliers" do
    before do
      create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
      partnership = create(:revenue_partnership, name: "Romane & Stéphanie")
      create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: romane, weight: 1)
      create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: stephanie, weight: 1)
    end

    it "met en commun la part d'atelier comme celle de production" do
      # Atelier animé par ROMANE SEULE : sa part brute est doublée par rapport
      # à Stéphanie, mais le partenariat remet les deux à égalité.
      create(:artisan_revenue_share, artisan: romane, percent: 100, active_from: Date.new(2026, 1, 1))
      create(:workshop, held_on: workshop_date, revenue_cents: 30_000, artisans: [ romane ])

      result = report
      settlements = result.artisan_settlements.index_by { |s| s.artisan.name }

      expect(settlements.keys).to contain_exactly("Romane", "Stéphanie")
      # 50/50 malgré l'absence de Stéphanie à l'atelier : « toujours 50/50,
      # même absent ». À un centime près : le reliquat d'arrondi va au poids le
      # plus lourd, comportement existant du partage par partenariat.
      expect(settlements["Romane"].settled_cents)
        .to be_within(1).of(settlements["Stéphanie"].settled_cents)
    end

    it "compte la part d'atelier dans le cumul BRUT de l'artisan qui l'a animé" do
      create(:workshop, held_on: workshop_date, revenue_cents: 30_000, artisans: [ romane ])

      totals = report.artisan_totals.index_by { |t| t.artisan.name }

      # Romane : sa part de production + 50 % des 21 000 de l'atelier.
      expect(totals["Romane"].amount_cents).to be > totals["Stéphanie"].amount_cents
      expect(totals["Romane"].amount_cents - totals["Stéphanie"].amount_cents).to eq(10_500)
    end

    it "ne compte pas un atelier comme un jour de production" do
      create(:workshop, held_on: workshop_date, revenue_cents: 30_000, artisans: [ romane ])

      totals = report.artisan_totals.index_by { |t| t.artisan.name }

      # Une seule journée de production sur la période, atelier compris.
      expect(totals["Romane"].days_count).to eq(1)
    end
  end
end
