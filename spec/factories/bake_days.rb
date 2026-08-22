FactoryBot.define do
  factory :bake_day do
    # Default to next Tuesday
    baked_on { Date.current.next_occurring(:tuesday) }
    cut_off_at { BakeDay.calculate_cut_off_for(baked_on) || 2.days.ago }

    # Toute fournée ouvre au moins le lieu de retrait par défaut (#148) — comme
    # en production, où « Les 4 Sources » est créé par migration et coché
    # automatiquement sur chaque nouvelle fournée. Sans lui, les commandes n'ont
    # aucun lieu où retomber.
    before(:create) do
      PickupLocation.default_location || FactoryBot.create(:pickup_location, :default)
    end

    trait :tuesday do
      baked_on { Date.current.next_occurring(:tuesday) }
      cut_off_at { BakeDay.calculate_cut_off_for(baked_on) }
    end

    trait :friday do
      baked_on { Date.current.next_occurring(:friday) }
      cut_off_at { BakeDay.calculate_cut_off_for(baked_on) }
    end

    trait :past do
      baked_on { Date.current.prev_occurring(:tuesday) }
      cut_off_at { BakeDay.calculate_cut_off_for(baked_on) }
    end

    trait :cut_off_passed do
      cut_off_at { 1.hour.ago }
    end

    trait :can_order do
      cut_off_at { 2.days.from_now }
    end
  end
end
