# frozen_string_literal: true

# Partenariat de revenu boulangers (#54 — évolution).
#
# Regroupe des artisans qui METTENT EN COMMUN leur revenu brut (part de leurs
# jours de production respectifs) sur une période, puis se le répartissent selon
# le poids de chaque membre (`weight`, 1 = parts égales par défaut). Cas concret :
# Romane et Stéphanie additionnent leurs jours du mois et se partagent 50/50,
# même si l'une est absente sur la période.
#
# La mise en commun est calculée au moment du rapport (cf. BakerRevenueService) ;
# rien n'est stocké ici que la composition et les poids. Un artisan hors
# partenariat garde son revenu brut tel quel.
class RevenuePartnership < ApplicationRecord
  has_many :revenue_partnership_memberships, dependent: :destroy
  has_many :artisans, through: :revenue_partnership_memberships

  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }
end
