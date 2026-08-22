FactoryBot.define do
  factory :bread_bag_price do
    amount_cents { 4 } # 0,04 €
    active_from { Date.new(2026, 1, 1) }
  end
end
