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
