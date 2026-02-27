class Customer < ApplicationRecord
  has_many :customer_groups, dependent: :destroy
  has_many :groups, through: :customer_groups
  has_one :wallet, dependent: :destroy
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

  # Returns the highest discount percent among all groups the customer belongs to.
  # Used when a customer has multiple groups with discounts: apply the best one.
  def effective_discount_percent
    groups.maximum(:discount_percent) || 0
  end

  # Returns the group with the highest discount (for display purposes).
  # When multiple groups have discounts, this is the one that determines the applied rate.
  def best_discount_group
    groups.order(discount_percent: :desc).first
  end

  # Backward compatibility: returns best_discount_group for JSON serialization and views
  # that expect customer.group (e.g. order modal, cart display).
  def group
    best_discount_group
  end

  def opt_out_sms!
    update!(sms_opt_out: true)
  end

  def opt_in_sms!
    update!(sms_opt_out: false)
  end
end

