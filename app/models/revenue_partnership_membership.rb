# frozen_string_literal: true

# Appartenance d'un artisan à un partenariat de revenu, avec son poids de
# répartition (#54 — évolution). `weight` pilote la clé de partage dans la mise
# en commun : à poids égaux (défaut 1), la répartition est équitable (50/50 pour
# deux membres) ; un poids différent permet un partage pondéré (ex. 60/40) sans
# toucher au moteur de calcul.
#
# Un artisan appartient à AU PLUS un partenariat (contrainte d'unicité en base et
# ici) : la couche de règlement est unique par artisan.
class RevenuePartnershipMembership < ApplicationRecord
  belongs_to :revenue_partnership
  belongs_to :artisan

  validates :weight, presence: true,
                     numericality: { greater_than_or_equal_to: 0 }
  validates :artisan_id, uniqueness: {
    message: "appartient déjà à un partenariat"
  }
end
