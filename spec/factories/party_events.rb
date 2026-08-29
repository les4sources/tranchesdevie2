FactoryBot.define do
  factory :party_event do
    kind { :public_party }
    held_on { Date.current + 7 }
    title { "Pizza Party publique" }
    capacity { 40 }
    registration_closes_at { 5.days.from_now }

    trait :public_party do
      kind { :public_party }
      title { "Pizza Party publique" }
      slot { nil }
      capacity { 40 }
      registration_closes_at { 5.days.from_now }
    end

    # Ventes agrégées importées d'une billetterie externe (BilletWeb) : pas de
    # commandes, la compta vient des compteurs portés par l'événement.
    trait :historical do
      kind { :public_party }
      historical_source { "billetweb" }
      historical_adults { 30 }
      historical_children { 10 }
      historical_sourciers { 0 }
      historical_fees_cents { 0 }
      capacity { nil }
      registration_closes_at { nil }
    end

    trait :private_party do
      kind { :private_party }
      title { nil }
      slot { :soir }
      capacity { nil }
      registration_closes_at { nil }
    end
  end

  factory :party_slot_block do
    blocked_on { Date.current + 7 }
    slot { :soir }
  end
end
