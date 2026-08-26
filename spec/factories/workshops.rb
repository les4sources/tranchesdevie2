FactoryBot.define do
  factory :workshop do
    sequence(:title) { |n| "Atelier pain #{n}" }
    held_on { Date.current }
    description { "Un atelier de fabrication du pain au levain." }
    notes { "Prévoir 12 tabliers." }
    revenue_cents { 30_000 }
  end
end
