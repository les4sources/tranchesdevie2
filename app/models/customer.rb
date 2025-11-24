class Customer < ApplicationRecord
  belongs_to :group, optional: true
  has_many :orders, dependent: :restrict_with_error
  has_many :phone_verifications, dependent: :destroy
  has_many :sms_messages, dependent: :nullify

  # Attribut virtuel pour permettre de sauter la validation du téléphone (utilisé par l'admin)
  attr_accessor :skip_phone_validation

  validates :first_name, presence: true
  validates :phone_e164, presence: true, uniqueness: { allow_nil: true }, unless: :skip_phone_validation
  validates :phone_e164, format: { with: /\A\+[1-9]\d{1,14}\z/, message: 'must be in E.164 format' }, if: -> { phone_e164.present? }

  scope :with_sms_enabled, -> { where(sms_opt_out: false) }

  def sms_enabled?
    phone_e164.present? && !sms_opt_out?
  end

  def full_name
    [first_name, last_name].compact.join(' ')
  end

  def opt_out_sms!
    update!(sms_opt_out: true)
  end

  def opt_in_sms!
    update!(sms_opt_out: false)
  end
end

