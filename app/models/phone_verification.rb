class PhoneVerification < ApplicationRecord
  OTP_TTL = 15.minutes
  MAX_ATTEMPTS = 5
  COOLDOWN_PERIOD = 20.seconds

  # A verification is keyed by EITHER a phone number (SMS channel) or an email
  # address (email channel) — the two login channels are at parity.
  validate :phone_or_email_present
  validates :code, presence: true, length: { is: 6 }, format: { with: /\A\d{6}\z/ }
  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :for_phone, ->(phone) { where(phone_e164: phone) }
  scope :for_email, ->(email) { where(email: email) }

  def expired?
    expires_at < Time.current
  end

  def max_attempts_reached?
    attempts_count >= MAX_ATTEMPTS
  end

  def increment_attempts!
    increment!(:attempts_count)
  end

  def self.generate_code
    rand(100_000..999_999).to_s
  end

  def self.create_for_phone(phone_e164)
    create_with_code(phone_e164: phone_e164)
  end

  def self.create_for_email(email)
    create_with_code(email: email)
  end

  def self.create_with_code(phone_e164: nil, email: nil)
    create!(
      phone_e164: phone_e164,
      email: email,
      code: generate_code,
      expires_at: Time.current + OTP_TTL,
      attempts_count: 0
    )
  end

  # Cooldown is enforced per channel target (a given phone or a given email).
  def self.can_send_new?(phone_e164)
    can_send_new_for?(phone: phone_e164)
  end

  def self.can_send_new_for?(phone: nil, email: nil)
    scope = phone ? for_phone(phone) : for_email(email)
    last_verification = scope.order(created_at: :desc).first
    return true if last_verification.nil?

    last_verification.created_at + COOLDOWN_PERIOD < Time.current
  end

  private

  def phone_or_email_present
    return if phone_e164.present? || email.present?

    errors.add(:base, "A phone number or an email is required")
  end
end
