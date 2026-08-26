FactoryBot.define do
  factory :ingredient_price do
    ingredient
    amount_cents { 1_200 } # 12 € / kg
    active_from { Date.new(2026, 1, 1) }
  end

  factory :flour_price do
    flour
    amount_cents { 90 } # 0,90 € / kg
    active_from { Date.new(2026, 1, 1) }
  end
end
