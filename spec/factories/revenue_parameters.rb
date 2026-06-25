FactoryBot.define do
  factory :revenue_parameter do
    key { RevenueParameter::TRANSPORT }
    value { 1_500 } # 15 € / jour
    active_from { Date.new(2026, 1, 1) }

    trait :transport do
      key { RevenueParameter::TRANSPORT }
      value { 1_500 }
    end

    trait :four_sources_rate do
      key { RevenueParameter::FOUR_SOURCES_RATE }
      value { 3_000 } # 30 % en points de base
    end
  end
end
