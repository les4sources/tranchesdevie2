FactoryBot.define do
  factory :group do
    sequence(:name) { |n| "Groupe #{n}" }
    discount_percent { 0 }
  end

  factory :customer_group do
    customer
    group
  end

  factory :group_product_discount do
    group
    discount_kind { "percent" }
    discount_value { 10 }

    trait :percent do
      discount_kind { "percent" }
      discount_value { 10 }
    end

    trait :fixed do
      discount_kind { "fixed" }
      discount_value { 200 } # 2,00 €
    end
  end
end
