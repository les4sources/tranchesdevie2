FactoryBot.define do
  factory :mold_type do
    sequence(:name) { |n| "Moule #{n}" }
    sequence(:position) { |n| n }
    limit { 100 }
  end
end
