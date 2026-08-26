# frozen_string_literal: true

# Une fournée au sens des boulangers (#194) : le sous-ensemble de pains qu'ils
# enfournent d'un coup, quand le pétrin et le four ne permettent pas de tout
# passer en une fois. Un jour de cuisson en porte 1 à N.
#
# La répartition est MANUELLE et le reste : rien ici ne propose ni n'applique de
# découpe automatique — décision explicite des boulangers du 25/08/2026, parce
# que les contraintes réelles (ordre de sortie des froments, livraisons, marché)
# ne sont pas modélisables.
class Batch < ApplicationRecord
  belongs_to :bake_day
  # Une fournée supprimée ne détruit jamais une ligne de commande : les lignes
  # redeviennent simplement non affectées.
  has_many :order_items, dependent: :nullify

  validates :name, presence: true, length: { maximum: 60 }
  validates :position, presence: true, numericality: { only_integer: true }

  scope :ordered, -> { order(position: :asc, id: :asc) }

  # Nom par défaut de la prochaine fournée : « Fournée 1 », « Fournée 2 »… en
  # suivant le rang, pas le compte, pour qu'une suppression au milieu ne
  # rebaptise pas les autres.
  def self.next_default_name(bake_day)
    "Fournée #{(bake_day.batches.maximum(:position) || 0) + 1}"
  end

  def self.next_position(bake_day)
    (bake_day.batches.maximum(:position) || 0) + 1
  end
end
