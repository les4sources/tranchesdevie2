FactoryBot.define do
  factory :variant_cost_price do
    product_variant
    amount_cents { 67 } # 0,67 €
    active_from { Date.new(2026, 1, 1) }
  end
end
