require "rails_helper"

# #208 — répartition de la recette des ateliers.
#
# Le point de vigilance : la réunion du 25/08/2026 n'a PAS tranché le partage
# boulangers / 4 Sources sur un atelier. Le taux est donc un paramètre
# historisé, et tant qu'il n'est pas saisi, un atelier n'est réparti à personne.
RSpec.describe WorkshopRevenueService do
  let(:date) { Date.new(2026, 9, 10) }

  let(:romane) { create(:artisan, name: "Romane") }
  let(:stephanie) { create(:artisan, name: "Stéphanie") }

  before do
    create(:artisan_revenue_share, artisan: romane, percent: 50, active_from: Date.new(2026, 1, 1))
    create(:artisan_revenue_share, artisan: stephanie, percent: 50, active_from: Date.new(2026, 1, 1))
  end

  def workshop(revenue_cents: 30_000, artisans: [], held_on: date)
    create(:workshop, held_on: held_on, revenue_cents: revenue_cents, artisans: artisans)
  end

  describe "tant que le taux n'est pas tranché" do
    it "n'attribue rien, mais conserve et affiche la recette" do
      result = described_class.call([ workshop(artisans: [ romane ]) ])
      entry = result.workshops.first

      expect(entry.revenue_cents).to eq(30_000)
      expect(entry.four_sources_cents).to eq(0)
      expect(entry.bakers_cents).to eq(0)
      expect(entry.rate_undefined?).to be true
      expect(entry.distributed?).to be false
      expect(result.undistributed_count).to eq(1)
    end
  end

  context "avec un taux configuré (30 % aux 4 Sources)" do
    before { create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1)) }

    it "partage la RECETTE, pas une marge brute" do
      entry = described_class.call([ workshop(revenue_cents: 30_000, artisans: [ romane ]) ]).workshops.first

      expect(entry.four_sources_cents).to eq(9_000)
      expect(entry.bakers_cents).to eq(21_000)
      expect(entry.four_sources_cents + entry.bakers_cents).to eq(entry.revenue_cents)
    end

    it "attribue la totalité de la part boulangers à un animateur unique à 100 %" do
      solo = create(:artisan, name: "Thomas")
      create(:artisan_revenue_share, artisan: solo, percent: 100, active_from: Date.new(2026, 1, 1))

      entry = described_class.call([ workshop(revenue_cents: 30_000, artisans: [ solo ]) ]).workshops.first

      expect(entry.artisan_shares.size).to eq(1)
      expect(entry.artisan_shares.first.amount_cents).to eq(21_000)
    end

    it "répartit entre deux animateurs selon leur pourcentage configuré" do
      entry = described_class.call([ workshop(revenue_cents: 30_000, artisans: [ romane, stephanie ]) ]).workshops.first

      amounts = entry.artisan_shares.map(&:amount_cents)
      expect(amounts).to eq([ 10_500, 10_500 ])
      expect(amounts.sum).to eq(entry.bakers_cents)
    end

    it "signale un atelier sans animateur, sans rien attribuer" do
      entry = described_class.call([ workshop(revenue_cents: 30_000, artisans: []) ]).workshops.first

      expect(entry.unassigned).to be true
      expect(entry.bakers_cents).to eq(0)
      expect(entry.four_sources_cents).to eq(0)
      expect(entry.distributed?).to be false
    end

    it "historise le taux : un nouveau palier n'affecte pas le passé" do
      create(:revenue_parameter, :workshop_rate, value: 5_000, active_from: Date.new(2026, 10, 1))

      september = described_class.call([ workshop(held_on: Date.new(2026, 9, 10), artisans: [ romane ]) ]).workshops.first
      october = described_class.call([ workshop(held_on: Date.new(2026, 10, 15), artisans: [ romane ]) ]).workshops.first

      expect(september.four_sources_cents).to eq(9_000)   # 30 %
      expect(october.four_sources_cents).to eq(15_000)    # 50 %
    end

    it "totalise la période" do
      result = described_class.call([
        workshop(revenue_cents: 30_000, artisans: [ romane ]),
        workshop(revenue_cents: 20_000, artisans: [ stephanie ])
      ])

      expect(result.total_revenue_cents).to eq(50_000)
      expect(result.total_four_sources_cents).to eq(15_000)
      expect(result.total_bakers_cents).to eq(35_000)
      expect(result.undistributed_count).to eq(0)
    end
  end
end
