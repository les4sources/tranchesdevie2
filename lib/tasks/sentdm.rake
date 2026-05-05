namespace :sentdm do
  desc "Crée/met à jour les templates SMS Sent.dm depuis config/sms_templates.yml"
  task sync_templates: :environment do
    SmsTemplatesSeeder.call
  end
end
