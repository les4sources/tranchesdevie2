FactoryBot.define do
  factory :sms_template do
    sequence(:name) { |n| "template_#{n}" }
    category { "UTILITY" }
    language { "fr" }
    body { "Bonjour {{0:name}}" }
    variables { [ { "id" => 0, "name" => "name", "sample" => "Lucas" } ] }
    sequence(:external_id) { |n| "tmpl_#{n}" }
    synced_at { Time.current }

    trait :unsynced do
      external_id { nil }
      synced_at { nil }
    end
  end
end
