FactoryBot.define do
  factory :partial_refund do
    order
    amount_cents { 550 }
    channel { :wallet }
    reason { "Pain manquant" }
  end

  factory :partial_refund_item do
    partial_refund
    order_item { partial_refund.order.order_items.first || create(:order_item, order: partial_refund.order) }
    qty { 1 }
    amount_cents { 550 }
  end
end
