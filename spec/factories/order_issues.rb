FactoryBot.define do
  factory :order_issue do
    order
    customer { order.customer }
    description { "Il manquait un pain dans mon sac." }
    state { :open }

    trait :resolved do
      state { :resolved }
      resolved_at { Time.current }
    end
  end

  factory :order_issue_item do
    order_issue
    order_item { order_issue.order.order_items.first || create(:order_item, order: order_issue.order) }
    qty { 1 }
  end
end
