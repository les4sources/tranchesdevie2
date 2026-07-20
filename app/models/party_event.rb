class PartyEvent < ApplicationRecord
  has_soft_deletion

  # Type d'événement party (#pizza-parties).
  enum :kind, { public_party: 0, private_party: 1 }, prefix: :kind
  # Créneau : requis en privé, optionnel en public.
  enum :slot, { midi: 0, soir: 1 }, prefix: :slot

  # Commandes rattachées à l'événement (inscriptions publiques / réservation privée).
  has_many :orders, dependent: :nullify

  validates :held_on, presence: true
  validates :kind, presence: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :slot, presence: true, if: :kind_private_party?
  # Une party PUBLIQUE est organisée par la boulangerie : capacité et clôture des
  # inscriptions sont obligatoires ; elle n'a pas de créneau (toujours en soirée).
  validates :title, presence: true, if: :kind_public_party?
  validates :capacity, presence: true, if: :kind_public_party?
  validates :registration_closes_at, presence: true, if: :kind_public_party?

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :public_events, -> { kind_public_party }
  scope :private_events, -> { kind_private_party }
  scope :upcoming, -> { not_deleted.where(held_on: Date.current..).order(:held_on, :slot) }

  SLOT_LABELS = { "midi" => "Midi", "soir" => "Soir" }.freeze

  # Capacité par créneau des parties PRIVÉES (réglage singleton).
  def self.private_slot_capacity
    ProductionSetting.current.private_party_slot_capacity
  end

  # Un (date, créneau) privé est-il réservable ? Ouvert par défaut ; indisponible
  # si la date est passée, si l'admin l'a bloqué, si une party PUBLIQUE (toujours en
  # soirée) occupe déjà cette date le soir, ou si la capacité (nombre de parties
  # privées déjà sur ce créneau) est atteinte.
  def self.private_slot_available?(date, slot)
    return false if date.blank? || slot.blank?
    return false if date.to_date < Date.current
    return false if PartySlotBlock.blocked?(date, slot)
    return false if slot.to_s == "soir" && public_party_scheduled?(date)

    private_events.not_deleted.where(held_on: date, slot: slot).count < private_slot_capacity
  end

  # Une party publique est-elle programmée à cette date ? (Publiques = soirée.)
  def self.public_party_scheduled?(date)
    public_events.not_deleted.where(held_on: date).exists?
  end

  def slot_label
    SLOT_LABELS[slot] || "—"
  end

  # Inscriptions ouvertes pour un événement PUBLIC ?
  def registration_open?
    return false unless kind_public_party? && active?

    registration_closes_at.nil? || registration_closes_at.future?
  end
end
