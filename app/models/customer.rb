class Customer < ApplicationRecord
  has_many :customer_groups, dependent: :destroy
  has_many :groups, through: :customer_groups
  has_one :wallet, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :sms_messages, dependent: :nullify
  has_many :email_messages, dependent: :nullify
  has_many :invoices, dependent: :destroy

  # Attribut virtuel pour permettre de sauter la validation du téléphone (utilisé par l'admin)
  attr_accessor :skip_phone_validation

  # L'e-mail est une identité de connexion à part entière (au même niveau que le
  # GSM) : on le normalise en minuscules et on garantit son unicité applicative.
  before_validation :normalize_email

  validates :first_name, presence: true
  validates :phone_e164, presence: true, uniqueness: { allow_nil: true }, unless: :skip_phone_validation
  validates :phone_e164, format: { with: /\A\+[1-9]\d{1,14}\z/, message: "must be in E.164 format" }, if: -> { phone_e164.present? }
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true

  scope :with_sms_enabled, -> { where(sms_opt_out: false) }
  scope :with_email_enabled, -> { where.not(email: [ nil, "" ]).where(email_opt_out: false) }
  # Clients professionnels (épiceries, points de dépôt) facturés mensuellement.
  scope :billable, -> { where(billable: true) }

  def sms_enabled?
    phone_e164.present? && !sms_opt_out?
  end

  # Whether non-OTP emails (e.g. order confirmations) may be sent to this customer.
  # OTP emails are always allowed and bypass this check.
  def email_enabled?
    email.present? && !email_opt_out?
  end

  def full_name
    [ first_name, last_name ].compact.join(" ")
  end

  # Returns the highest discount percent among all groups the customer belongs to.
  # Used when a customer has multiple groups with discounts: apply the best one.
  def effective_discount_percent
    groups.maximum(:discount_percent) || 0
  end

  # Dernier point de retrait choisi par le client (#148) : sert à pré-remplir le
  # sélecteur du calendrier. On ignore les commandes annulées et les lieux
  # supprimés. Retombe sur nil — l'appelant utilise alors le lieu par défaut.
  def last_pickup_location
    orders.where.not(status: :cancelled)
          .where.not(pickup_location_id: nil)
          .order(created_at: :desc)
          .joins(:pickup_location)
          .merge(PickupLocation.not_deleted)
          .first
          &.pickup_location
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

  def opt_out_email!
    update!(email_opt_out: true)
  end

  def opt_in_email!
    update!(email_opt_out: false)
  end

  private

  def normalize_email
    self.email = email.strip.downcase if email.present?
  end
end
