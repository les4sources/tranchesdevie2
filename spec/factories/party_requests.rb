FactoryBot.define do
  factory :party_request do
    customer
    # Premier mardi ou vendredi au-delà du préavis de 10 jours : une date plus
    # proche serait refusée par le service, et une date fixe casserait la spec
    # deux jours par semaine.
    held_on do
      (PartyRequest::MINIMUM_NOTICE_DAYS..(PartyRequest::MINIMUM_NOTICE_DAYS + 14))
        .map { |n| Date.current + n }
        .find { |date| PartyEvent::PRIVATE_WDAYS.include?(date.wday) }
    end
    slot { "soir" }
    forfait { true }
    customer_note { "Anniversaire de Jules, on arrive vers 18h30." }
    state { :pending }

    trait :accepted do
      state { :accepted }
      decided_at { Time.current }
      decided_by { "Romane" }
    end

    trait :refused do
      state { :refused }
      decided_at { Time.current }
      decided_by { "Romane" }
      decision_reason { "Le four est déjà pris par un autre groupe ce soir-là." }
    end
  end
end
