FactoryBot.define do
  factory :customer do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    sequence(:phone_e164) { |n| "+3247#{n.to_s.rjust(7, '0')}" }
    email { Faker::Internet.email }
    sms_opt_out { false }

    trait :with_sms_disabled do
      sms_opt_out { true }
    end

    trait :without_phone do
      phone_e164 { nil }
      skip_phone_validation { true }
    end
  end
end
