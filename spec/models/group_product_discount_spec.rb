require 'rails_helper'

RSpec.describe GroupProductDiscount, type: :model do
  let(:group) { create(:group, discount_percent: 0) }
  let(:product) { create(:product) }
  let(:variant) { create(:product_variant, product: product, price_cents: 700) }

  describe 'validations' do
    it 'requires exactly one target (product or variant)' do
      d = build(:group_product_discount, group: group, product: nil, product_variant: nil)
      expect(d).not_to be_valid
      expect(d.errors[:base].join).to include("produit ou une variante")
    end

    it 'rejects both a product and a variant at once' do
      d = build(:group_product_discount, group: group, product: product, product_variant: variant)
      expect(d).not_to be_valid
    end

    it 'rejects a percent above 100' do
      d = build(:group_product_discount, :percent, group: group, product: product, discount_value: 150)
      expect(d).not_to be_valid
    end

    it 'enforces one rule per (group, variant)' do
      create(:group_product_discount, :percent, group: group, product_variant: variant)
      dup = build(:group_product_discount, :percent, group: group, product_variant: variant)
      expect(dup).not_to be_valid
    end
  end

  describe '#unit_discount_cents' do
    it 'computes a percent reduction' do
      d = build(:group_product_discount, :percent, group: group, product: product, discount_value: 50)
      expect(d.unit_discount_cents(700)).to eq(350)
    end

    it 'computes a fixed (cents) reduction' do
      d = build(:group_product_discount, :fixed, group: group, product: product, discount_value: 500)
      expect(d.unit_discount_cents(700)).to eq(500)
    end

    it 'never makes the price negative (floors the reduction at the price)' do
      d = build(:group_product_discount, :fixed, group: group, product: product, discount_value: 900)
      expect(d.unit_discount_cents(700)).to eq(700)
    end
  end

  describe 'target/discount_value_raw round-tripping' do
    it 'maps target to product_variant_id' do
      d = described_class.new(group: group)
      d.target = "variant_#{variant.id}"
      expect(d.product_variant_id).to eq(variant.id)
      expect(d.product_id).to be_nil
    end

    it 'converts euros input to cents for fixed discounts' do
      d = build(:group_product_discount, group: group, product: product, discount_kind: "fixed")
      d.discount_value_raw = "2,50"
      d.valid?
      expect(d.discount_value).to eq(250)
    end

    it 'keeps the integer percent for percent discounts' do
      d = build(:group_product_discount, group: group, product: product, discount_kind: "percent")
      d.discount_value_raw = "30"
      d.valid?
      expect(d.discount_value).to eq(30)
    end

    # Régression : modifier UNIQUEMENT la valeur d'une remise existante via les
    # nested attributes du groupe doit persister. Un simple attr_writer ne
    # rendait aucune colonne dirty → autosave sautait l'enfant en silence.
    it 'persists a value-only change through the group nested attributes' do
      d = create(:group_product_discount, group: group, product: product,
                                          discount_kind: "percent", discount_value: 10)

      group.update!(group_product_discounts_attributes: [
        { id: d.id.to_s, target: "product_#{product.id}", discount_kind: "percent",
          discount_value_raw: "25", _destroy: "false" }
      ])

      expect(d.reload.discount_value).to eq(25)
    end

    it 'persists a kind switch with its converted value' do
      d = create(:group_product_discount, group: group, product: product,
                                          discount_kind: "percent", discount_value: 10)

      group.update!(group_product_discounts_attributes: [
        { id: d.id.to_s, target: "product_#{product.id}", discount_kind: "fixed",
          discount_value_raw: "2,50", _destroy: "false" }
      ])

      expect(d.reload.discount_kind).to eq("fixed")
      expect(d.reload.discount_value).to eq(250)
    end
  end
end
