# Demande de réservation d'une Pizza party PRIVÉE (#pizza-parties).
#
# Une demande n'est pas une réservation : elle n'occupe aucun créneau, ne crée ni
# `PartyEvent` ni `Order`, et ne consomme aucune capacité. C'est la VALIDATION de
# la boulangerie qui fait naître les deux, et l'encaissement qui confirme.
#
# Le modèle est volontairement distinct d'`Order` : il porte des champs qui n'ont
# rien à faire sur une commande (motif de refus, décideur, relance interne), et
# une demande refusée ne doit laisser aucune carcasse dans les tables comptables.
# Il est TERMINAL à `accepted` : à partir de là, tout ce qui concerne le client
# (à payer, payée, expirée, remboursée) se lit sur l'`Order` — une seule machine
# à états à la fois.
class PartyRequest < ApplicationRecord
  belongs_to :customer
  # Nul tant que la demande n'est pas validée.
  belongs_to :order, optional: true
  has_many :party_request_items, dependent: :destroy

  enum :slot, { midi: 0, soir: 1 }, prefix: :slot
  enum :state, {
    pending: 0,      # en attente d'une réponse de la boulangerie
    accepted: 1,     # validée : l'Order existe, le paiement est attendu
    refused: 2,      # refusée par la boulangerie, avec motif
    cancelled: 3,    # annulée par le client avant réponse
    expired: 4       # jamais traitée : clôturée automatiquement à J-3
  }, prefix: :state

  validates :held_on, :slot, :estimated_persons, :customer_note, presence: true
  validates :estimated_persons, numericality: { only_integer: true, greater_than: 0 }
  validates :customer_note, length: { maximum: Order::CUSTOMER_NOTE_MAX_LENGTH }
  validates :public_token, presence: true, uniqueness: true
  # Le motif est obligatoire sur un refus — c'est tout ce que le client recevra
  # comme explication (ISC-21).
  validates :decision_reason, presence: true, if: :state_refused?

  before_validation :generate_public_token, on: :create

  scope :awaiting_decision, -> { state_pending.order(:held_on, :slot) }
  scope :awaiting_payment, -> { state_accepted.joins(:order).where(orders: { status: Order.statuses[:awaiting_payment] }) }
  scope :for_date, ->(date) { where(held_on: date) }

  # Préavis minimum : une demande vise une date à au moins 10 jours (#pizza-parties).
  # Le boulanger doit avoir le temps de répondre, et le client de payer.
  MINIMUM_NOTICE_DAYS = 10

  # Heure de tous les rendez-vous datés du parcours (sollicitation J-5, relance
  # J-4, échéance J-3). Une seule heure pour les trois : pas d'e-mail à minuit,
  # et pas trois échéances au même instant.
  DEADLINE_HOUR = 9
  DEADLINE_ZONE = "Europe/Brussels"

  # Instant de sollicitation du paiement : J-5 à 9 h.
  def self.payment_prompt_at(held_on)
    at_hour(held_on.to_date - 5)
  end

  # Instant de relance : J-4 à 9 h.
  def self.payment_reminder_at(held_on)
    at_hour(held_on.to_date - 4)
  end

  # Échéance de paiement, et terme de la clôture automatique d'une demande jamais
  # traitée : J-3 à 9 h.
  def self.deadline_at(held_on)
    at_hour(held_on.to_date - 3)
  end

  def self.at_hour(date)
    ActiveSupport::TimeZone[DEADLINE_ZONE].local(date.year, date.month, date.day, DEADLINE_HOUR, 0, 0)
  end

  # Une date est-elle demandable ? Jour et créneau ouverts (mardi/vendredi soir),
  # non bloqués, sans party publique — ET à au moins 10 jours.
  def self.requestable?(date, slot)
    return false if date.blank? || slot.blank?
    return false unless PartyEvent.private_bookable_slot?(date, slot)
    return false if date.to_date < Date.current + MINIMUM_NOTICE_DAYS
    return false if PartySlotBlock.blocked?(date, slot)
    return false if slot.to_s == "soir" && PartyEvent.public_party_scheduled?(date)

    true
  end

  # Disponibilité sur une plage, pour le calendrier du formulaire de demande.
  # Une demande n'occupant aucun créneau, la capacité n'entre PAS dans ce calcul :
  # seules les parties confirmées (donc payées) peuvent rendre une date complète.
  def self.requestable_availability(range)
    capacity = PartyEvent.private_slot_capacity
    slot_names = PartySlotBlock.slots.invert
    blocked = PartySlotBlock.where(blocked_on: range)
                            .pluck(:blocked_on, :slot)
                            .map { |date, slot| [ date, slot && (slot.is_a?(Integer) ? slot_names[slot] : slot.to_s) ] }
                            .to_set
    public_dates = PartyEvent.public_events.not_deleted.where(held_on: range).distinct.pluck(:held_on).to_set
    counts = PartyEvent.private_events.not_deleted.where(held_on: range).group(:held_on, :slot).count
    floor = Date.current + MINIMUM_NOTICE_DAYS

    range.each_with_object({}) do |date, map|
      map[date] = PartyEvent::SLOT_LABELS.keys.index_with do |slot|
        next false unless PartyEvent.private_bookable_slot?(date, slot)
        next false if date < floor
        next false if blocked.include?([ date, slot ]) || blocked.include?([ date, nil ])
        next false if slot == "soir" && public_dates.include?(date)

        counts.fetch([ date, slot ], 0) < capacity
      end
    end
  end

  def slot_label
    PartyEvent::SLOT_LABELS.fetch(slot.to_s, slot.to_s)
  end

  def deadline_at
    self.class.deadline_at(held_on)
  end

  def payment_prompt_at
    self.class.payment_prompt_at(held_on)
  end

  # Total ANNONCÉ à la demande : les prix unitaires figés × le nombre estimé.
  # Le montant réellement dû est recalculé au paiement sur le nombre confirmé,
  # avec ces mêmes prix unitaires (ISC-28 / ISC-66).
  def estimated_total_cents
    party_request_items.sum { |item| item.qty * item.unit_price_cents - item.discount_cents }
  end

  # La boulangerie peut-elle encore répondre ? Non si déjà traitée, non si la
  # clôture automatique est passée.
  def decidable?
    state_pending? && Time.current < deadline_at
  end

  private

  def generate_public_token
    return if public_token.present?

    loop do
      self.public_token = SecureRandom.alphanumeric(24)
      break unless PartyRequest.exists?(public_token: public_token)
    end
  end
end
