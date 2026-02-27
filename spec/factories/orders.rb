FactoryBot.define do
  factory :order do
    customer
    bake_day
    status { :paid }
    total_cents { 1100 }
    requires_invoice { false }

    trait :pending do
      status { :pending }
    end

    trait :paid do
      status { :paid }
    end

    trait :ready do
      status { :ready }
    end

    trait :picked_up do
      status { :picked_up }
    end

    trait :cancelled do
      status { :cancelled }
    end

    trait :unpaid do
      status { :unpaid }
    end

    trait :planned do
      status { :planned }
      source { :calendar }
    end

    trait :from_calendar do
      source { :calendar }
    end

    trait :with_items do
      transient do
        items_count { 2 }
      end

      after(:create) do |order, evaluator|
        create_list(:order_item, evaluator.items_count, order: order)
        order.update!(total_cents: order.order_items.sum { |i| i.qty * i.unit_price_cents })
      end
    end
  end
end
