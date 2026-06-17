require 'rails_helper'

# ISC-86: garde-fou de commande pour les variantes restreintes à certains jours de cuisson.
RSpec.describe OrderCreationService do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, channel: 'store') }
  let(:friday) { Date.current.next_occurring(:friday) }
  let(:bake_day) { create(:bake_day, baked_on: friday, cut_off_at: 2.days.from_now) }

  def cart_for(variant)
    [ { "product_variant_id" => variant.id.to_s, "qty" => 1 } ]
  end

  it 'rejects a variant not available on the bake day weekday' do
    variant = create(:product_variant, :tuesday_only, product: product)
    service = described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant), skip_capacity_check: true
    )

    expect(service.call).to be false
    expect(service.errors.join).to include("n'est pas disponible le vendredi")
  end

  it 'accepts a variant available on the bake day weekday' do
    variant = create(:product_variant, :friday_only, product: product)
    service = described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant), skip_capacity_check: true
    )

    expect(service.call).to be_a(Order)
    expect(service.errors).to be_empty
  end

  it 'accepts an unrestricted variant on any bake day weekday' do
    variant = create(:product_variant, product: product)
    service = described_class.new(
      customer: customer, bake_day: bake_day, cart_items: cart_for(variant), skip_capacity_check: true
    )

    expect(service.call).to be_a(Order)
  end
end
