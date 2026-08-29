FactoryBot.define do
  # Données INVENTÉES uniquement : le dépôt est public, aucun participant réel
  # ne doit s'y trouver (#206).
  factory :party_participant do
    party_event
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.unique.email }
    ticket_kind { "adult" }
    sequence(:external_reference) { |n| "CMD#{1000 + n}" }
    external_ticket_label { "Place adulte" }
    price_cents { 1_000 }
    external_paid { true }

    trait :child do
      ticket_kind { "child" }
      external_ticket_label { "Place enfant" }
      price_cents { 600 }
    end
  end
end
