# frozen_string_literal: true

class Artisan < ApplicationRecord
  has_many :bake_day_artisans, dependent: :destroy
  has_many :bake_days, through: :bake_day_artisans
  has_many :artisan_revenue_shares, dependent: :destroy

  # Un artisan appartient à au plus un partenariat de revenu (#54). En faire
  # partie fait que son revenu brut est mis en commun avec celui des autres
  # membres puis réparti (cf. RevenuePartnership / BakerRevenueService).
  has_one :revenue_partnership_membership, dependent: :destroy
  has_one :revenue_partnership, through: :revenue_partnership_membership

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  # Part de revenu (% littéral) applicable à une date donnée (#54). Renvoie le
  # palier le plus récent dont `active_from` est antérieure ou égale à `on`, ou
  # `nil` si aucune part n'est saisie à cette date (pas de défaut — la part est
  # configurée en admin). Versionnement par date : insensible aux paliers
  # postérieurs.
  def revenue_share_percent(on: Date.current)
    artisan_revenue_shares
      .where(active_from: ..on)
      .ordered
      .limit(1)
      .pick(:percent)
  end
end
