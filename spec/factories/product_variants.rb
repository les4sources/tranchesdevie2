FactoryBot.define do
  factory :product_variant do
    product
    sequence(:name) { |n| "Variant #{n}" }
    price_cents { 550 }
    active { true }
    channel { 'store' }

    trait :inactive do
      active { false }
    end

    trait :expensive do
      price_cents { 1500 }
    end

    trait :admin_channel do
      channel { 'admin' }
    end

    trait :tuesday_only do
      available_weekdays { [ 2 ] }
    end

    trait :friday_only do
      available_weekdays { [ 5 ] }
    end
  end
end
