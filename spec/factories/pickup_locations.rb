FactoryBot.define do
  factory :pickup_location do
    sequence(:name) { |n| "Point de retrait #{n}" }
    description { "Description affichée au client." }
    default { false }
    sequence(:position) { |n| n }

    # Le lieu par défaut (« Les 4 Sources » en production). Un seul à la fois :
    # `PickupLocation.default_location` doit rester libre avant de l'utiliser.
    trait :default do
      name { "Les 4 Sources" }
      description { "Retrait à la boulangerie des 4 Sources, sur le site de Bauche." }
      default { true }
      position { 0 }
    end

    trait :deleted do
      deleted_at { Time.current }
    end
  end
end
