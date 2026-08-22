# frozen_string_literal: true

# Paramètres généraux du calcul des revenus boulangers (#54), historisés par
# date d'activation. Même patron que BreadBagPrice (#52) : la valeur applicable
# à une date donnée est le palier le plus récent dont `active_from` est
# antérieure ou égale à la date.
#
# Deux clés gérées :
#   - "transport"         : coût de transport par jour de production, en CENTS
#                           (référence : 15 €/jour = 1500).
#   - "four_sources_rate" : taux de prélèvement des 4 Sources sur la marge brute,
#                           en POINTS DE BASE (référence : 30 % = 3000).
#
# Versionnement par date : un nouveau palier n'affecte jamais les périodes
# antérieures.
class RevenueParameter < ApplicationRecord
  TRANSPORT = "transport"
  FOUR_SOURCES_RATE = "four_sources_rate"
  KEYS = [ TRANSPORT, FOUR_SOURCES_RATE ].freeze

  # Valeurs de référence utilisées comme repli quand aucun palier n'est saisi
  # pour la date demandée (le moteur reste calculable « out of the box »).
  DEFAULT_TRANSPORT_CENTS = 1_500       # 15 € / jour de production
  DEFAULT_FOUR_SOURCES_BASIS_POINTS = 3_000 # 30 % de la marge brute

  # Valeur saisie en unités lisibles dans le formulaire admin (€ pour le
  # transport, % pour le taux). Non persistée : convertie vers `value` par le
  # contrôleur. Exposée ici pour que les helpers de formulaire Rails puissent la
  # lire/écrire.
  attr_accessor :value_input

  validates :key, presence: true, inclusion: { in: KEYS }
  validates :value, presence: true,
                    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :active_from, presence: true

  scope :ordered, -> { order(active_from: :desc, id: :desc) }
  scope :for_key, ->(key) { where(key: key) }

  # Valeur (entier) du paramètre `key` applicable à `date`, ou `nil` si aucun
  # palier n'est actif à cette date (pas de zéro trompeur — le repli applicatif
  # est géré par les méthodes dédiées ci-dessous).
  def self.value_on(key, date = Date.current)
    for_key(key).where(active_from: ..date).ordered.limit(1).pick(:value)
  end

  # Coût de transport (cents) applicable à `date`, avec repli sur la référence.
  def self.transport_cents_on(date = Date.current)
    value_on(TRANSPORT, date) || DEFAULT_TRANSPORT_CENTS
  end

  # Taux 4 Sources en points de base applicable à `date`, avec repli.
  def self.four_sources_basis_points_on(date = Date.current)
    value_on(FOUR_SOURCES_RATE, date) || DEFAULT_FOUR_SOURCES_BASIS_POINTS
  end
end
