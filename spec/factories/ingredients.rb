FactoryBot.define do
  factory :ingredient do
    sequence(:name) { |n| "Ingrédient #{n}" }
    unit_type { :weight }
    sequence(:position) { |n| n }
  end
end
