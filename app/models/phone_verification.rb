class PhoneVerification < ApplicationRecord
  OTP_TTL = 5.minutes
  MAX_ATTEMPTS = 5
  COOLDOWN_PERIOD = 20.seconds

  validates :phone_e164, presence: true
  validates :code, presence: true, length: { is: 6 }, format: { with: /\A\d{6}\z/ }
  validates :expires_at, presence: true

  scope :active, -> { where('expires_at > ?', Time.current) }
  scope :for_phone, ->(phone) { where(phone_e164: phone) }

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
    code = generate_code
    create!(
      phone_e164: phone_e164,
      code: code,
      expires_at: Time.current + OTP_TTL,
      attempts_count: 0
    )
  end

  def self.can_send_new?(phone_e164)
    last_verification = for_phone(phone_e164).order(created_at: :desc).first
    return true if last_verification.nil?

    last_verification.created_at + COOLDOWN_PERIOD < Time.current
  end
end

