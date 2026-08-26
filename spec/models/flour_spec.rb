require 'rails_helper'

RSpec.describe Flour, type: :model do
  describe 'levain type (#88)' do
    it 'accepts froment and seigle' do
      expect(build(:flour, levain_type: "froment")).to be_valid
      expect(build(:flour, :seigle)).to be_valid
    end

    it 'exposes enum predicates' do
      expect(build(:flour, :seigle).seigle?).to be true
      expect(build(:flour, levain_type: "froment").froment?).to be true
    end
  end

  describe 'ratios (#88)' do
    it 'requires the panification ratios' do
      flour = build(:flour, flour_ratio: nil)
      expect(flour).not_to be_valid
      expect(flour.errors[:flour_ratio]).to be_present
    end

    it 'rejects a negative ratio' do
      expect(build(:flour, water_ratio: -1)).not_to be_valid
    end
  end

  # Base pâte (décision boulangers 25/08/2026) : les quatre ratios sont des
  # fractions de la pâte, leur somme dit si la recette boucle.
  describe 'panification ratios sum' do
    it 'sums the four ratios' do
      flour = build(:flour, flour_ratio: 0.532, water_ratio: 0.391, salt_ratio: 0.012, levain_ratio: 0.120)
      expect(flour.panification_ratios_sum.to_f).to eq(1.055)
    end

    it 'reports the kneading margin above 100% of the dough' do
      flour = build(:flour, flour_ratio: 0.532, water_ratio: 0.391, salt_ratio: 0.012, levain_ratio: 0.120)
      expect(flour.panification_margin_percent).to eq(5.5)
    end

    it 'reports a negative margin when the recipe falls short of the dough weight' do
      flour = build(:flour, flour_ratio: 0.5, water_ratio: 0.3, salt_ratio: 0.01, levain_ratio: 0.09)
      expect(flour.panification_margin_percent).to eq(-10.0)
    end

    it 'reports no margin when the recipe closes exactly' do
      flour = build(:flour, flour_ratio: 0.55, water_ratio: 0.35, salt_ratio: 0.02, levain_ratio: 0.08)
      expect(flour.panification_margin_percent).to eq(0.0)
    end
  end

  describe 'price per kg' do
    it 'round-trips euros to cents' do
      flour = build(:flour)
      flour.price_per_kg_euros = "1,50"
      expect(flour.price_per_kg_cents).to eq(150)
      expect(flour.price_per_kg_euros).to eq(1.5)
    end

    it 'treats a blank input as no price' do
      flour = build(:flour)
      flour.price_per_kg_euros = ""
      expect(flour.price_per_kg_cents).to be_nil
    end

    it 'rejects a negative price' do
      expect(build(:flour, price_per_kg_cents: -100)).not_to be_valid
    end
  end
end
