FactoryBot.define do
  factory :artisan do
    sequence(:name) { |n| "Artisan #{n}" }
    active { true }

    trait :inactive do
      active { false }
    end
  end
end
