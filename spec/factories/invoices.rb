FactoryBot.define do
  factory :invoice do
    customer
    issued_on { Date.current }
    subtotal_cents { 1000 }
    vat_cents { 0 }
    total_cents { 1000 }
    vat_rate { 0 }
    # `number` est attribué automatiquement par le modèle (before_validation).

    trait :period do
      period_start { Date.current.beginning_of_month }
      period_end { Date.current.end_of_month }
    end
  end
end
