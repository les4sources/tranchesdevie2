FactoryBot.define do
  factory :sms_message do
    association :customer
    direction { :outbound }
    kind { :confirmation }
    sequence(:to_e164) { |n| "+3247000#{format('%04d', n)}" }
    from_e164 { "+32455136142" }
    body { "Ta commande est confirmée." }
    sent_at { Time.current }

    trait :inbound do
      direction { :inbound }
      kind { :other }
    end
  end
end
