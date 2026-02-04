FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Pain #{n}" }
    category { :breads }
    sequence(:position) { |n| n }
    active { true }
    channel { 'store' }

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
