class OtpService
  def self.send_otp(phone_e164)
    return { success: false, error: 'Phone number required' } if phone_e164.blank?

    # Check cooldown
    unless PhoneVerification.can_send_new?(phone_e164)
      return { success: false, error: 'Veuillez patienter 60 secondes avant de redemander un code' }
    end

    verification = PhoneVerification.create_for_phone(phone_e164)

    # In a real implementation, send SMS via Telerivet here
    # For MVP, we'll just log it (actual SMS sending should be done via job)
    Rails.logger.info("OTP for #{phone_e164}: #{verification.code}")

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
end

