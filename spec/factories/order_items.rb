FactoryBot.define do
  factory :order_item do
    order
    product_variant
    qty { 1 }
    unit_price_cents { 550 }

    trait :multiple do
      qty { 3 }
    end
  end
end
