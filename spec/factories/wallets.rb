FactoryBot.define do
  factory :wallet do
    customer
    balance_cents { 5000 }  # 50€
    low_balance_threshold_cents { 1000 }  # 10€

    trait :empty do
      balance_cents { 0 }
    end

    trait :low_balance do
      balance_cents { 500 }
    end

    trait :negative do
      balance_cents { -500 }
    end

    trait :rich do
      balance_cents { 50000 }  # 500€
    end
  end
end
