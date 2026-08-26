FactoryBot.define do
  factory :sales_location_cost do
    sales_location
    amount_cents { 2_500 } # 25,00 €
    valid_from { Date.new(2026, 1, 1) }
    valid_until { nil }
  end
end
