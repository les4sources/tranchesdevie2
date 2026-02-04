FactoryBot.define do
  factory :wallet_transaction do
    wallet
    amount_cents { 1000 }
    transaction_type { :top_up }

    trait :top_up do
      transaction_type { :top_up }
      amount_cents { 2000 }
    end

    trait :order_debit do
      transaction_type { :order_debit }
      amount_cents { -550 }
    end

    trait :order_refund do
      transaction_type { :order_refund }
      amount_cents { 550 }
    end
  end
end
