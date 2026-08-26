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

    # Taux 4 Sources des ATELIERS (#208). Sans palier saisi, un atelier reste
    # volontairement non réparti : la réunion n'a pas tranché ce partage.
    trait :workshop_rate do
      key { RevenueParameter::WORKSHOP_FOUR_SOURCES_RATE }
      value { 3_000 }
    end
  end
end
