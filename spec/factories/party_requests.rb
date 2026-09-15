FactoryBot.define do
  factory :party_request do
    customer
    # Premier mardi ou vendredi au-delà du préavis de 10 jours : une date plus
    # proche serait refusée par le service, et une date fixe casserait la spec
    # deux jours par semaine.
    held_on do
      (PartyRequest::MINIMUM_NOTICE_DAYS..(PartyRequest::MINIMUM_NOTICE_DAYS + 14))
        .map { |n| Date.current + n }
        .find { |date| PartyEvent::PRIVATE_WDAYS.include?(date.wday) }
    end
    slot { "soir" }
    forfait { true }
    customer_note { "Anniversaire de Jules, on arrive vers 18h30." }
    state { :pending }

    # Une demande porte TOUJOURS ses lignes de prix figées : c'est le contrat de
    # prix passé avec le client, et la validation en dépend pour construire la
    # commande.
    transient do
      paton_price_cents { 1200 }
      forfait_price_cents { 4000 }
    end

    after(:create) do |request, evaluator|
      next if request.party_request_items.any?

      paton = Product.find_by(pizza_party_role: :party) || create(:product, :pizza_party)
      paton_variant = paton.product_variants.first ||
                      create(:product_variant, product: paton, price_cents: evaluator.paton_price_cents)
      forfait = Product.find_by(pizza_party_role: :forfait) || create(:product, :pizza_party_forfait)
      forfait_variant = forfait.product_variants.first ||
                        create(:product_variant, product: forfait, price_cents: evaluator.forfait_price_cents, channel: "admin")

      create(:party_request_item, party_request: request, product_variant: paton_variant,
                                  qty: 1, unit_price_cents: paton_variant.price_cents)
      create(:party_request_item, party_request: request, product_variant: forfait_variant,
                                  qty: 1, unit_price_cents: forfait_variant.price_cents)
    end

    trait :accepted do
      state { :accepted }
      decided_at { Time.current }
      decided_by { "Romane" }
    end

    trait :refused do
      state { :refused }
      decided_at { Time.current }
      decided_by { "Romane" }
      decision_reason { "Le four est déjà pris par un autre groupe ce soir-là." }
    end
  end
end
