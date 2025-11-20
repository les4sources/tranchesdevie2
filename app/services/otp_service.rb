class OtpService
  TELERIVET_API_URL = 'https://api.telerivet.com/v1'

  def self.send_otp(phone_e164)
    return { success: false, error: 'Phone number required' } if phone_e164.blank?

    # Check cooldown
    unless PhoneVerification.can_send_new?(phone_e164)
      return { success: false, error: 'Veuillez patienter 20 secondes avant de redemander un code' }
    end

    verification = PhoneVerification.create_for_phone(phone_e164)

    # Find customer if exists
    customer = Customer.find_by(phone_e164: phone_e164)

    # Send SMS via Telerivet
    message = "Salut, c'est Tranches de Vie ! Voici votre code de connexion : #{verification.code}"
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
    return false unless api_key && project_id && phone_id

    response = HTTParty.post(
      "#{TELERIVET_API_URL}/projects/#{project_id}/messages/send",
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Basic #{Base64.strict_encode64("#{api_key}:")}"
      },
      body: {
        to_number: to,
        content: body,
        phone_id: phone_id
      }.to_json
    )

    if response.success?
      external_id = response['id']
      sent_at = Time.current
      SmsMessage.create!(
        direction: :outbound,
        to_e164: to,
        from_e164: phone_number,
        body: body,
        kind: :otp,
        external_id: external_id,
        customer_id: customer_id,
        sent_at: sent_at
      )
      true
    else
      Rails.logger.error("Failed to send OTP SMS: #{response.body}")
      false
    end
  rescue StandardError => e
    Rails.logger.error("OTP SMS Service Error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  def self.api_key
    ENV['TELERIVET_API_KEY']
  end

  def self.project_id
    ENV['TELERIVET_PROJECT_ID']
  end

  def self.phone_id
    ENV['TELERIVET_PHONE_ID']
  end

  def self.phone_number
    ENV['TELERIVET_PHONE_NUMBER'] || '+32XXXXXXXXX'
  end
end

