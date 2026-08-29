require "rails_helper"

# Ventilation du revenu d'un boulanger (#54).
#
# Un boulanger touche de l'argent de quatre sources qui n'ont pas le même
# barème : le pain (70/30 sur la marge), les pizza parties privées, les pizza
# parties publiques, les ateliers. Le rapport n'affichait qu'un total, sans dire
# d'où venait l'argent — et les parties publiques HISTORIQUES (BilletWeb), que
# la fondation doit rétroactivement aux boulangers, n'entraient nulle part.
#
# Ces specs verrouillent deux choses : l'argent BilletWeb arrive bien dans le
# pool, et la somme des quatre postes fait toujours le total versé — y compris
# après la mise en commun d'un partenariat, où chaque poste est réparti pour
# lui-même.
RSpec.describe "Ventilation du revenu par boulanger" do
  let(:friday) { Date.new(2026, 9, 4) }
  let(:saturday) { Date.new(2026, 9, 5) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:friday_bake) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:public_product) { create(:product, :pizza_party_public, name: "Pizza party publique") }
  let!(:adulte) do
    create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000,
                             party_four_sources_base_cents: 300, flour_quantity: 200)
  end
  let!(:enfant) do
    create(:product_variant, product: public_product, name: "enfant", price_cents: 500,
                             party_four_sources_base_cents: 150, flour_quantity: 200)
  end

  let(:customer) { create(:customer) }
  let(:romane) { create(:artisan, name: "Romane") }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: friday - 60)
    create(:variant_cost_price, product_variant: enfant, amount_cents: 26, active_from: friday - 60)
    create(:artisan_revenue_share, artisan: romane, percent: 100, active_from: Date.new(2026, 1, 1))
    create(:bake_day_artisan, bake_day: friday_bake, artisan: romane)
  end

  def report
    BakerRevenueService.new(start_date: friday - 30, end_date: friday + 30).call
  end

  describe "pizza parties publiques historiques (BilletWeb)" do
    it "fait entrer la part due par la fondation dans le pool des boulangers" do
      before_cents = report.baker_pool_cents

      create(:party_event, :historical, held_on: saturday,
                                        historical_adults: 30, historical_children: 10)

      after = report
      expected = HistoricalPartyRevenueService.call(PartyEvent.historical.first).bakers_cents

      expect(expected).to be > 0
      expect(after.baker_pool_cents).to eq(before_cents + expected)
      expect(after.total_historical_party_bakers_cents).to eq(expected)
      expect(after.total_historical_party_persons).to eq(40)
    end

    it "ne gonfle pas le chiffre d'affaires : cette recette n'a jamais transité par l'app" do
      before_revenue = report.total_revenue_cents

      create(:party_event, :historical, held_on: saturday)

      expect(report.total_revenue_cents).to eq(before_revenue)
    end

    it "verse cet argent au boulanger, dans le poste « party publique »" do
      create(:party_event, :historical, held_on: saturday,
                                        historical_adults: 30, historical_children: 10)

      settlement = report.artisan_settlements.find { |s| s.artisan.id == romane.id }
      due = HistoricalPartyRevenueService.call(PartyEvent.historical.first).bakers_cents

      expect(settlement.public_party_cents).to eq(due)
      expect(settlement.settled_cents).to eq(due)
    end

    it "rattache la party à la fournée qui la précède, jamais à deux" do
      create(:bake_day, baked_on: friday + 4, cut_off_at: friday + 2)
      create(:party_event, :historical, held_on: saturday)

      days_with_party = report.days.select { |day| day.historical_party_bakers_cents.positive? }

      expect(days_with_party.map(&:date)).to eq([ friday ])
    end
  end

  describe "somme des postes" do
    it "égale la part finale, pour un boulanger solo" do
      create(:party_event, :historical, held_on: saturday)
      order = create(:order, :paid, customer: customer, bake_day: nil,
                                    party_event: create(:party_event, :public_party, held_on: friday),
                                    pickup_location: default_pickup, total_cents: 5_000)
      create(:order_item, order: order, product_variant: adulte, qty: 5, unit_price_cents: 1_000)

      settlement = report.artisan_settlements.find { |s| s.artisan.id == romane.id }
      buckets = BakerRevenueService::BUCKETS.sum { |bucket| settlement.public_send(bucket) }

      expect(buckets).to eq(settlement.settled_cents)
    end

    it "égale la part finale de chaque membre d'un partenariat" do
      thomas = create(:artisan, name: "Thomas")
      create(:artisan_revenue_share, artisan: thomas, percent: 100, active_from: Date.new(2026, 1, 1))
      partnership = create(:revenue_partnership, name: "Romane et Thomas")
      create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: romane, weight: 1)
      create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: thomas, weight: 1)

      create(:party_event, :historical, held_on: saturday,
                                        historical_adults: 31, historical_children: 7)

      report.artisan_settlements.each do |settlement|
        buckets = BakerRevenueService::BUCKETS.sum { |bucket| settlement.public_send(bucket) }
        expect(buckets).to eq(settlement.settled_cents),
                           "#{settlement.artisan.name} : #{buckets} ≠ #{settlement.settled_cents}"
      end
    end

    it "conserve le pool total après mise en commun" do
      thomas = create(:artisan, name: "Thomas")
      create(:artisan_revenue_share, artisan: thomas, percent: 100, active_from: Date.new(2026, 1, 1))
      partnership = create(:revenue_partnership, name: "Romane et Thomas")
      create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: romane, weight: 1)
      create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: thomas, weight: 1)

      create(:party_event, :historical, held_on: saturday, historical_adults: 31, historical_children: 7)

      result = report
      expect(result.artisan_settlements.sum(&:settled_cents)).to eq(result.artisan_settlements.sum(&:raw_cents))
    end
  end

  describe "pool qui ne trouve personne" do
    it "signale une fournée sans boulanger affecté plutôt que d'absorber l'argent" do
      orphan = create(:bake_day, baked_on: friday + 7, cut_off_at: friday + 5)
      create(:party_event, :historical, held_on: orphan.baked_on)

      warning = report.warnings.find { |w| w.include?("ne sont versés à personne") }

      expect(warning).to be_present
      expect(warning).to include("aucun boulanger n'est affecté")
    end

    it "ne dit rien quand tout le pool est réparti" do
      create(:party_event, :historical, held_on: saturday)

      expect(report.warnings.grep(/ne sont versés à personne/)).to be_empty
    end
  end

  describe "party publique antérieure à toute fournée" do
    it "le dit au lieu de la perdre en silence" do
      create(:party_event, :historical, held_on: friday - 10)

      expect(report.warnings.join(" ")).to include("précède toute fournée")
    end
  end
end
