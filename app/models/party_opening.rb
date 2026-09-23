# Soir ouvert à la main aux parties PRIVÉES, en plus des jours de boulangerie
# (#pizza-parties).
#
# La règle de base n'ouvre que le mardi et le vendredi soir, parce que le four y
# est déjà chaud. Mais une demande de groupe tombe parfois un samedi, et la
# boulangerie veut pouvoir dire oui : cette table est la liste de ces oui-là.
#
# Toujours le SOIR — le midi n'est plus proposé — donc pas de colonne `slot` :
# une date suffit à tout dire.
#
# Une ouverture n'est pas une réservation : elle rend le soir RÉSERVABLE, sans
# rien occuper. Les autres règles continuent de s'appliquer dessus (blocage,
# party publique, capacité, délai de réservation).
class PartyOpening < ApplicationRecord
  validates :opened_on, presence: true, uniqueness: true

  scope :upcoming, -> { where(opened_on: Date.current..).order(:opened_on) }
  scope :on_range, ->(range) { where(opened_on: range) }

  # Ce soir-là est-il ouvert à la main ?
  def self.open_on?(date)
    return false if date.blank?

    exists?(opened_on: date)
  end

  # Une ouverture posée un jour de boulangerie ne sert à rien : la règle ouvre
  # déjà ce soir-là. On le DIT dans l'admin plutôt que de refuser la saisie —
  # rien n'est cassé, c'est juste sans effet.
  def redundant?
    opened_on.present? && PartyEvent::PRIVATE_WDAYS.include?(opened_on.wday)
  end
end
