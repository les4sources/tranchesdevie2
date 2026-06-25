# Prix d'un sac à pain, paramètre général historisé par date d'activation (#52).
# Le prix applicable à une date donnée est le palier le plus récent dont
# `active_from` est antérieure ou égale à la date. Versionnement par date :
# changer le prix ne modifie jamais les périodes antérieures. Consommé par le
# calcul des bénéfices (#54) via Order#bread_bags_cost_cents.
class BreadBagPrice < ApplicationRecord
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :active_from, presence: true

  scope :ordered, -> { order(active_from: :desc, id: :desc) }

  # Prix (cents) applicable à `date`, ou nil si aucun palier n'est actif à cette
  # date (pas de zéro trompeur).
  def self.amount_cents_on(date = Date.current)
    where(active_from: ..date).ordered.limit(1).pick(:amount_cents)
  end
end
