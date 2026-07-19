FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Pain #{n}" }
    category { :breads }
    sequence(:position) { |n| n }
    active { true }
    channel { 'store' }
    internal_category { :boulangerie }
    pizza_party_role { :none }

    trait :epicerie do
      internal_category { :epicerie }
    end

    trait :traiteur do
      internal_category { :traiteur }
    end

    trait :autre do
      internal_category { :autre }
    end

    trait :bread do
      category { :breads }
    end

    trait :dough_ball do
      category { :dough_balls }
    end

    trait :inactive do
      active { false }
    end

    trait :admin_channel do
      channel { 'admin' }
    end

    # Produit « Pizza party privée » (#68) : déclenche le forfait.
    trait :pizza_party do
      category { :dough_balls }
      pizza_party_role { :party }
    end

    # Produit forfait Pizza party (#68) : admin channel, compté une fois.
    trait :pizza_party_forfait do
      category { :dough_balls }
      channel { 'admin' }
      pizza_party_role { :forfait }
    end

    # Produit « Pizza party publique » (#pizza-parties) : variantes adulte/enfant,
    # pas de forfait, barème compta dédié (base 4S par variante).
    trait :pizza_party_public do
      category { :dough_balls }
      pizza_party_role { :public_party }
    end
  end
end
