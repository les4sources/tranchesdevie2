FactoryBot.define do
  factory :flour do
    sequence(:name) { |n| "Farine #{n}" }
    sequence(:position) { |n| n }
    levain_type { "froment" }
    flour_ratio { 0.5556 }
    water_ratio { 0.655 }
    salt_ratio { 0.022 }
    levain_ratio { 0.12095 }

    trait :seigle do
      levain_type { "seigle" }
    end
  end
end
