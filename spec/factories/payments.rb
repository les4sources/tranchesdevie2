FactoryBot.define do
  factory :payment do
    order
    sequence(:stripe_payment_intent_id) { |n| "pi_test_#{n}" }
    status { :succeeded }

    trait :refunded do
      status { :refunded }
    end

    trait :failed do
      status { :failed }
    end
  end
end
