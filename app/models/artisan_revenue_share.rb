# frozen_string_literal: true

# Part de revenu d'un artisan dans le pool boulangers, historisée par date
# d'activation (#54). Même patron que VariantCostPrice (#90) / BreadBagPrice
# (#52) : la part applicable à une date donnée est le palier le plus récent dont
# `active_from` est antérieure ou égale à la date (cf. Artisan#revenue_share_percent).
#
# Versionnement par date : ajouter un nouveau palier ne modifie jamais la part
# des périodes antérieures. Aucune valeur par défaut — la part est saisie en
# admin (décision Michael 25/06). `percent` est un pourcentage LITTÉRAL
# (ex. 50.0 = 50 %), jamais normalisé : la répartition du pool applique la part
# telle quelle, et un avertissement est levé si la somme des présents dépasse
# 100 % (cf. BakerRevenueService).
class ArtisanRevenueShare < ApplicationRecord
  belongs_to :artisan

  validates :percent, presence: true,
                      numericality: { greater_than_or_equal_to: 0 }
  validates :active_from, presence: true

  scope :ordered, -> { order(active_from: :desc, id: :desc) }
end
