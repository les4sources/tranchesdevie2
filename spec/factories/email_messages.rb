FactoryBot.define do
  factory :email_message do
    association :customer
    direction { :outbound }
    kind { :confirmation }
    sequence(:to_email) { |n| "eater#{n}@example.com" }
    from_email { "boulangerie@les4sources.be" }
    subject { "Ta commande chez Tranches de Vie" }
    body_html { "<p>Merci pour ta commande !</p>" }
    sent_at { Time.current }

    trait :otp do
      kind { :otp }
      order { nil }
      subject { "Ton code de connexion" }
      body_html { "<p>123456</p>" }
    end
  end
end
