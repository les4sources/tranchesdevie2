FactoryBot.define do
  factory :party_request_item do
    party_request
    product_variant
    qty { 1 }
    unit_price_cents { 1200 }
    discount_cents { 0 }
  end
end
