FactoryBot.define do
  factory :flour do
    sequence(:name) { |n| "Farine #{n}" }
    sequence(:position) { |n| n }
    levain_type { "froment" }
    # Ratio de la boulangerie : quatre fractions de la PÂTE (somme 1,055, soit
    # 5,5 % de marge de pétrissage).
    flour_ratio { 0.532 }
    water_ratio { 0.391 }
    salt_ratio { 0.012 }
    levain_ratio { 0.120 }

    trait :seigle do
      levain_type { "seigle" }
    end
  end
end
