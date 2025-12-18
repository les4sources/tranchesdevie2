class OtpService
  SMSTOOLS_API_URL = 'https://api.smsgatewayapi.com/v1/message/send'

  def self.send_otp(phone_e164)
    return { success: false, error: 'Phone number required' } if phone_e164.blank?

    # Check cooldown
    unless PhoneVerification.can_send_new?(phone_e164)
      return { success: false, error: 'Veuillez patienter 20 secondes avant de redemander un code' }
    end

    verification = PhoneVerification.create_for_phone(phone_e164)

    # Find customer if exists
    customer = Customer.find_by(phone_e164: phone_e164)

    # Send SMS via Smstools
    message = "Salut, c'est Tranches de Vie ! Voici ton code de connexion pour passer ta commande : #{verification.code}"
    sms_sent = send_otp_sms(
      to: phone_e164,
      body: message,
      customer_id: customer&.id
    )

    unless sms_sent
      verification.destroy # Remove verification if SMS failed
      return { success: false, error: 'Erreur lors de l\'envoi du SMS. Veuillez réessayer.' }
    end

    { success: true, verification_id: verification.id }
  rescue StandardError => e
    Rails.logger.error("OTP Service Error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    { success: false, error: 'Une erreur est survenue' }
  end

  def self.verify_otp(phone_e164, code)
    verification = PhoneVerification.for_phone(phone_e164)
                                    .active
                                    .order(created_at: :desc)
                                    .first

    return { success: false, error: 'Code invalide ou expiré' } unless verification

    if verification.max_attempts_reached?
      return { success: false, error: 'Trop de tentatives. Veuillez redemander un code' }
    end

    verification.increment_attempts!

    if verification.code == code && !verification.expired?
      verification.destroy # Remove used OTP
      { success: true }
    else
      error = verification.expired? ? 'Code expiré' : 'Code incorrect'
      { success: false, error: error }
    end
  end

  private

  def self.send_otp_sms(to:, body:, customer_id: nil)
    unless client_id.present? && client_secret.present? && sender.present?
      Rails.logger.error("OTP Service - Missing configuration: client_id=#{client_id.present?}, client_secret=#{client_secret.present?}, sender=#{sender.present?}")
      return false
    end

    # Format phone number: remove + if present (Smstools expects international format without +)
    formatted_to = to.to_s.gsub(/^\+/, '')

    # Use test mode in development (validates parameters but doesn't send SMS or consume credits)
    test_mode = !Rails.env.production?

    # Log request details
    Rails.logger.info("OTP Service (#{Rails.env}): To: #{formatted_to}, Sender: #{sender}, Test: #{test_mode}")
    Rails.logger.debug("OTP Service - Client ID present: #{client_id.present?}, Client Secret present: #{client_secret.present?}, Sender present: #{sender.present?}")

    request_body = {
      message: body,
      to: formatted_to,
      sender: sender,
      test: test_mode
    }

    response = HTTParty.post(
      SMSTOOLS_API_URL,
      headers: {
        'Content-Type' => 'application/json',
        'X-Client-Id' => client_id,
        'X-Client-Secret' => client_secret
      },
      body: request_body.to_json
    )

    Rails.logger.info("OTP Service - Response status: #{response.code}, Success: #{response.success?}")
    Rails.logger.debug("OTP Service - Response body: #{response.body}")

    if response.success?
      # Smstools returns {"messageid": "..."} for single recipient
      external_id = response['messageid'] || (response['messageids']&.first)
      sent_at = Time.current
      SmsMessage.create!(
        direction: :outbound,
        to_e164: to,
        from_e164: sender,
        body: body,
        kind: :otp,
        external_id: external_id,
        customer_id: customer_id,
        sent_at: sent_at
      )
      Rails.logger.info("OTP Service - SMS sent successfully. External ID: #{external_id}")
      true
    else
      Rails.logger.error("Failed to send OTP SMS - Status: #{response.code}, Body: #{response.body}, Request: #{request_body.inspect}")
      false
    end
  rescue StandardError => e
    Rails.logger.error("OTP SMS Service Error: #{e.class} - #{e.message}")
    Rails.logger.error("OTP SMS Service Error Backtrace: #{e.backtrace.first(5).join("\n")}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  def self.client_id
    ENV['SMSTOOLS_CLIENT_ID']
  end

  def self.client_secret
    ENV['SMSTOOLS_CLIENT_SECRET']
  end

  def self.sender
    ENV['SMSTOOLS_SENDER']
  end
end

