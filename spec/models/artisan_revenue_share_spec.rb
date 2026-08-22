require "rails_helper"

# Part de revenu d'un artisan, historisée par date (#54). Même contrat que
# VariantCostPrice (#90) : le palier applicable à une date est le plus récent
# dont `active_from` <= date, et un nouveau palier n'affecte pas le passé.
RSpec.describe ArtisanRevenueShare, type: :model do
  describe "validations" do
    it "exige un pourcentage et une date d'activation" do
      share = ArtisanRevenueShare.new(artisan: create(:artisan))
      expect(share).not_to be_valid
      expect(share.errors[:percent]).to be_present
      expect(share.errors[:active_from]).to be_present
    end

    it "refuse un pourcentage négatif" do
      share = build(:artisan_revenue_share, percent: -1)
      expect(share).not_to be_valid
    end
  end

  describe "Artisan#revenue_share_percent" do
    let(:artisan) { create(:artisan) }

    it "renvoie nil quand aucune part n'est saisie (pas de défaut)" do
      expect(artisan.revenue_share_percent(on: Date.new(2026, 5, 1))).to be_nil
    end

    it "renvoie le palier le plus récent dont active_from <= date" do
      create(:artisan_revenue_share, artisan: artisan, percent: 50, active_from: Date.new(2026, 1, 1))
      create(:artisan_revenue_share, artisan: artisan, percent: 60, active_from: Date.new(2026, 4, 1))

      expect(artisan.revenue_share_percent(on: Date.new(2026, 3, 15))).to eq(50)
      expect(artisan.revenue_share_percent(on: Date.new(2026, 5, 1))).to eq(60)
    end

    it "ignore les paliers postérieurs à la date demandée (versionnement par date)" do
      create(:artisan_revenue_share, artisan: artisan, percent: 50, active_from: Date.new(2026, 1, 1))
      create(:artisan_revenue_share, artisan: artisan, percent: 70, active_from: Date.new(2026, 6, 1))

      # Une date AVANT le nouveau palier voit toujours l'ancienne part.
      expect(artisan.revenue_share_percent(on: Date.new(2026, 5, 31))).to eq(50)
    end

    it "renvoie nil pour une date antérieure au tout premier palier" do
      create(:artisan_revenue_share, artisan: artisan, percent: 50, active_from: Date.new(2026, 3, 1))
      expect(artisan.revenue_share_percent(on: Date.new(2026, 2, 1))).to be_nil
    end
  end
end
