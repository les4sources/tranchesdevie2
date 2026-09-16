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

  validates :held_on, :slot, :customer_note, presence: true
  # Le nombre de participants n'est PAS demandé ici : il n'aide pas le boulanger
  # à décider (le four et le pétrin, eux, sont contrôlés au paiement) et le
  # client ne le connaît pas encore. Il l'arrête au règlement.
  validates :estimated_persons, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
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

  DEADLINE_ZONE = "Europe/Brussels"

  # Délai entre la sollicitation de paiement et le cut-off de la fournée.
  PROMPT_BEFORE_CUT_OFF = 48.hours

  # Cut-off de la fournée qui pétrira les pâtons.
  #
  # Une party privée a TOUJOURS lieu un jour de cuisson (mardi ou vendredi) : son
  # cut-off est donc celui de la fournée du jour même. C'est le moment où la
  # boulangerie fige son plan de production — après lui, un nombre de
  # participants n'a plus de sens.
  #
  # La fournée n'existe pas toujours en base au moment où on calcule (elles sont
  # créées quelques jours à l'avance) : on retombe alors sur la règle, qui est la
  # même (`BakeDay.calculate_cut_off_for`).
  def self.cut_off_for(held_on)
    date = held_on.to_date
    BakeDay.find_by(baked_on: date)&.cut_off_at || BakeDay.calculate_cut_off_for(date)
  end

  # Instant de sollicitation du paiement : 48 h avant le cut-off.
  def self.payment_prompt_at(held_on)
    cut_off = cut_off_for(held_on)
    cut_off && cut_off - PROMPT_BEFORE_CUT_OFF
  end

  # Échéance de paiement : le cut-off lui-même.
  def self.deadline_at(held_on)
    cut_off_for(held_on)
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

  # Prix unitaire figé d'un pâton, remise groupe déduite. Il n'y a pas de total à
  # annoncer à la demande : le nombre de participants n'est arrêté qu'au paiement.
  def paton_unit_price_cents
    item = party_request_items.includes(product_variant: :product)
                              .find { |i| i.product_variant.product.pizza_party_role_party? }
    item&.net_unit_price_cents || 0
  end

  # Forfait figé (dû quel que soit le nombre de participants).
  def forfait_cents
    party_request_items.includes(product_variant: :product)
                       .reject { |i| i.product_variant.product.pizza_party_role_party? }
                       .sum(&:total_cents)
  end

  # La boulangerie peut-elle encore répondre ? Non si déjà traitée, non au-delà du
  # cut-off de la fournée — après lui, plus personne ne peut pétrir pour ce groupe.
  def decidable?
    return false unless state_pending?

    deadline = deadline_at
    deadline.nil? || Time.current < deadline
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
