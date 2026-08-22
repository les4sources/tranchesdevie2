FactoryBot.define do
  factory :sales_location do
    sequence(:name) { |n| "Marché #{n}" }
    active { true }
    sequence(:position) { |n| n }

    trait :deleted do
      deleted_at { Time.current }
    end
  end
end
