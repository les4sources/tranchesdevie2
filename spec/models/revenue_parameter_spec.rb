require "rails_helper"

# Paramètres généraux historisés du calcul de revenus (#54) : transport (cents)
# et taux 4 Sources (points de base). Même contrat de versionnement par date que
# BreadBagPrice (#52).
RSpec.describe RevenueParameter, type: :model do
  describe "validations" do
    it "refuse une clé inconnue" do
      param = build(:revenue_parameter, key: "inconnu")
      expect(param).not_to be_valid
    end

    it "exige une valeur entière positive et une date" do
      param = RevenueParameter.new(key: RevenueParameter::TRANSPORT)
      expect(param).not_to be_valid
      expect(param.errors[:value]).to be_present
      expect(param.errors[:active_from]).to be_present
    end
  end

  describe ".value_on" do
    it "renvoie le palier le plus récent dont active_from <= date" do
      create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
      create(:revenue_parameter, :transport, value: 1_800, active_from: Date.new(2026, 4, 1))

      expect(described_class.value_on(RevenueParameter::TRANSPORT, Date.new(2026, 3, 1))).to eq(1_500)
      expect(described_class.value_on(RevenueParameter::TRANSPORT, Date.new(2026, 5, 1))).to eq(1_800)
    end

    it "renvoie nil quand aucun palier n'est défini pour la clé/date" do
      expect(described_class.value_on(RevenueParameter::TRANSPORT, Date.new(2026, 1, 1))).to be_nil
    end

    it "isole les clés entre elles" do
      create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
      expect(described_class.value_on(RevenueParameter::TRANSPORT, Date.new(2026, 2, 1))).to be_nil
    end
  end

  describe "résolveurs avec repli sur la référence" do
    it "transport_cents_on retombe sur 1500 sans palier" do
      expect(described_class.transport_cents_on(Date.new(2026, 1, 1))).to eq(1_500)
    end

    it "four_sources_basis_points_on retombe sur 3000 sans palier" do
      expect(described_class.four_sources_basis_points_on(Date.new(2026, 1, 1))).to eq(3_000)
    end

    it "utilise le palier saisi quand il existe" do
      create(:revenue_parameter, :four_sources_rate, value: 2_500, active_from: Date.new(2026, 2, 1))
      expect(described_class.four_sources_basis_points_on(Date.new(2026, 3, 1))).to eq(2_500)
    end
  end
end
