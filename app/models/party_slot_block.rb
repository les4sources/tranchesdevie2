class PartySlotBlock < ApplicationRecord
  # Créneau bloqué : nul = toute la journée (les deux créneaux).
  enum :slot, { midi: 0, soir: 1 }, prefix: :slot

  validates :blocked_on, presence: true
  validates :blocked_on, uniqueness: { scope: :slot }

  scope :on_date, ->(date) { where(blocked_on: date) }

  # Un (date, créneau) est-il bloqué ? Un blocage sans créneau (slot nil) couvre
  # toute la journée.
  def self.blocked?(date, slot)
    where(blocked_on: date).where(slot: [ nil, slot ]).exists?
  end
end
