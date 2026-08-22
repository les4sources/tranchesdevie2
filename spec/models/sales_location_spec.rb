require "rails_helper"

# Lieu de vente (#150) et coût historisé par période de validité.
RSpec.describe SalesLocation do
  describe "validations" do
    it "exige un nom" do
      expect(build(:sales_location, name: nil)).not_to be_valid
    end

    it "refuse un nom dupliqué parmi les lieux non supprimés" do
      create(:sales_location, name: "Marché d'Anhée")
      expect(build(:sales_location, name: "Marché d'Anhée")).not_to be_valid
    end

    it "autorise le même nom qu'un lieu supprimé (soft delete)" do
      create(:sales_location, :deleted, name: "Marché d'Anhée")
      expect(build(:sales_location, name: "Marché d'Anhée")).to be_valid
    end
  end

  describe "soft deletion" do
    it "conserve le lieu lisible après suppression, hors du scope not_deleted" do
      location = create(:sales_location)
      location.soft_delete!

      expect(location.reload.deleted_at).to be_present
      expect(SalesLocation.not_deleted).not_to include(location)
      expect(SalesLocation.find(location.id)).to eq(location)
    end
  end

  describe "scopes" do
    it "active ne renvoie que les lieux actifs et non supprimés" do
      active = create(:sales_location, active: true)
      create(:sales_location, active: false)
      create(:sales_location, :deleted, active: true)

      expect(SalesLocation.active).to contain_exactly(active)
    end
  end

  describe "#cost_cents" do
    let(:location) { create(:sales_location) }

    it "renvoie nil si aucune période ne couvre la date" do
      create(:sales_location_cost, sales_location: location,
             amount_cents: 2_000, valid_from: Date.new(2026, 6, 1))

      expect(location.cost_cents(on: Date.new(2026, 5, 31))).to be_nil
    end

    it "renvoie le coût d'une période ouverte (valid_until nil) à partir de valid_from" do
      create(:sales_location_cost, sales_location: location,
             amount_cents: 2_000, valid_from: Date.new(2026, 1, 1), valid_until: nil)

      expect(location.cost_cents(on: Date.new(2026, 1, 1))).to eq(2_000)
      expect(location.cost_cents(on: Date.new(2027, 12, 31))).to eq(2_000)
    end

    it "respecte les bornes d'une période fermée (valid_from..valid_until inclus)" do
      create(:sales_location_cost, sales_location: location,
             amount_cents: 3_000, valid_from: Date.new(2026, 3, 1), valid_until: Date.new(2026, 3, 31))

      expect(location.cost_cents(on: Date.new(2026, 2, 28))).to be_nil
      expect(location.cost_cents(on: Date.new(2026, 3, 1))).to eq(3_000)
      expect(location.cost_cents(on: Date.new(2026, 3, 31))).to eq(3_000)
      expect(location.cost_cents(on: Date.new(2026, 4, 1))).to be_nil
    end

    it "sélectionne la bonne période quand le coût évolue dans le temps" do
      create(:sales_location_cost, sales_location: location,
             amount_cents: 2_000, valid_from: Date.new(2026, 1, 1), valid_until: Date.new(2026, 6, 30))
      create(:sales_location_cost, sales_location: location,
             amount_cents: 2_500, valid_from: Date.new(2026, 7, 1), valid_until: nil)

      expect(location.cost_cents(on: Date.new(2026, 5, 15))).to eq(2_000)
      expect(location.cost_cents(on: Date.new(2026, 7, 15))).to eq(2_500)
    end
  end

  describe SalesLocationCost do
    it "refuse une fin antérieure au début" do
      cost = build(:sales_location_cost,
                   valid_from: Date.new(2026, 3, 1), valid_until: Date.new(2026, 2, 1))
      expect(cost).not_to be_valid
    end

    it "convertit amount_euros vers amount_cents" do
      cost = build(:sales_location_cost, amount_cents: nil)
      cost.amount_euros = "25,50"
      expect(cost.amount_cents).to eq(2_550)
    end
  end
end
