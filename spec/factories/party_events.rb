FactoryBot.define do
  factory :party_event do
    kind { :public_party }
    held_on { Date.current + 7 }
    title { "Pizza Party publique" }

    trait :public_party do
      kind { :public_party }
      title { "Pizza Party publique" }
      slot { nil }
    end

    trait :private_party do
      kind { :private_party }
      title { nil }
      slot { :soir }
    end
  end

  factory :party_slot_block do
    blocked_on { Date.current + 7 }
    slot { :soir }
  end
end
