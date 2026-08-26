FactoryBot.define do
  factory :revenue_partnership do
    sequence(:name) { |n| "Partenariat #{n}" }
    active { true }

    trait :inactive do
      active { false }
    end
  end
end
