FactoryBot.define do
  factory :customer do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    # Le numéro et l'e-mail portent un préfixe propre au PROCESSUS de test.
    #
    # La base de test est partagée entre plusieurs agents et n'est pas remise à
    # zéro entre les runs : une séquence qui repart de 1 à chaque processus
    # finissait par buter sur des lignes laissées par un run précédent
    # (« Phone e164 est déjà utilisé »), et faisait tomber des specs au hasard,
    # loin de ce qu'elles testaient.
    sequence(:phone_e164) { |n| "+32#{(Process.pid % 1000).to_s.rjust(3, '0')}#{n.to_s.rjust(6, '0')}" }
    sequence(:email) { |n| "client-#{Process.pid}-#{n}@example.test" }
    sms_opt_out { false }

    trait :with_sms_disabled do
      sms_opt_out { true }
    end

    trait :with_email_disabled do
      email_opt_out { true }
    end

    trait :without_email do
      email { nil }
    end

    trait :without_phone do
      phone_e164 { nil }
      skip_phone_validation { true }
    end
  end
end
