FactoryBot.define do
  factory :batch do
    bake_day
    sequence(:name) { |n| "Fournée #{n}" }
    sequence(:position) { |n| n }
  end
end
