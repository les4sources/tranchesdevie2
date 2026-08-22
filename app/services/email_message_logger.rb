# Records every outbound email into the EmailMessage table so the admin can
# review (and resend) what was sent to a customer — mirror of how OtpService /
# SmsService log SmsMessage records.
#
# Mailers attach metadata via custom headers (set before calling `mail`):
#   X-Customer-Id, X-Email-Kind (confirmation/otp/other), X-Order-Id
class EmailMessageLogger
  def self.record(mail)
    return if mail.nil?

    EmailMessage.create!(
      direction: :outbound,
      to_email: Array(mail.to).first,
      from_email: Array(mail.from).first,
      subject: mail.subject,
      body_html: extract_html(mail),
      kind: header_value(mail, "X-Email-Kind").presence || "other",
      customer_id: header_value(mail, "X-Customer-Id").presence,
      order_id: header_value(mail, "X-Order-Id").presence,
      message_id: mail.message_id,
      sent_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("EmailMessageLogger failed: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  def self.header_value(mail, name)
    mail[name]&.value
  end

  def self.extract_html(mail)
    if mail.multipart?
      mail.html_part&.body&.decoded || mail.text_part&.body&.decoded || mail.body.decoded
    else
      mail.body.decoded
    end
  end
end
