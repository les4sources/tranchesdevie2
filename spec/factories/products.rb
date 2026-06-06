FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Pain #{n}" }
    category { :breads }
    sequence(:position) { |n| n }
    active { true }
    channel { 'store' }
    internal_category { :boulangerie }

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
  end
end
