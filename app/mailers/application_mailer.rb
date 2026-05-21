class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "boulangerie@les4sources.be")
  layout "mailer"

  after_action :log_email

  private

  # Journalise chaque e-mail sortant dans EmailMessage (cf. EmailMessageLogger).
  def log_email
    EmailMessageLogger.record(message)
  end
end
