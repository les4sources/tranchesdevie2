class OtpService
  def self.send_otp(phone_e164)
    return { success: false, error: "Phone number required" } if phone_e164.blank?

    unless PhoneVerification.can_send_new?(phone_e164)
      return { success: false, error: "Veuillez patienter 20 secondes avant de redemander un code" }
    end

    verification = PhoneVerification.create_for_phone(phone_e164)
    customer = Customer.find_by(phone_e164: phone_e164)

    sms_sent = send_otp_sms(
      to: phone_e164,
      code: verification.code,
      customer: customer
    )

    unless sms_sent
      verification.destroy
      return { success: false, error: "Erreur lors de l'envoi du SMS. Veuillez réessayer." }
    end

    { success: true, verification_id: verification.id }
  rescue StandardError => e
    Rails.logger.error("OTP Service Error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    { success: false, error: "Une erreur est survenue" }
  end

  def self.verify_otp(phone_e164, code)
    verification = PhoneVerification.for_phone(phone_e164)
                                    .active
                                    .order(created_at: :desc)
                                    .first

    return { success: false, error: "Code invalide ou expiré" } unless verification

    if verification.max_attempts_reached?
      return { success: false, error: "Trop de tentatives. Veuillez redemander un code" }
    end

    verification.increment_attempts!

    if verification.code == code && !verification.expired?
      verification.destroy
      { success: true }
    else
      error = verification.expired? ? "Code expiré" : "Code incorrect"
      { success: false, error: error }
    end
  end

  def self.send_otp_sms(to:, code:, customer:)
    response = SentDmClient.send_message(
      template_name: :otp,
      to: to,
      parameters: { code: code }
    )

    external_id = response&.data&.recipients&.first&.message_id
    body = response&.data&.recipients&.first&.body || SmsService.rendered_body(:otp, code: code)

    SmsMessage.create!(
      direction: :outbound,
      to_e164: to,
      from_e164: SmsService.sender,
      body: body,
      kind: :otp,
      external_id: external_id,
      customer_id: customer&.id,
      sent_at: Time.current
    )
    true
  rescue StandardError => e
    Rails.logger.error("OTP Service - échec envoi à #{to}: #{e.class} #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end
end
