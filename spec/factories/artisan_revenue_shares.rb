FactoryBot.define do
  factory :artisan_revenue_share do
    artisan
    percent { 50 }
    active_from { Date.new(2026, 1, 1) }
  end
end
