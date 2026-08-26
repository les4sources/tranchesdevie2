# frozen_string_literal: true

# Partenariats de revenu boulangers (#54 — évolution).
#
# Un partenariat regroupe plusieurs artisans qui METTENT EN COMMUN leur revenu
# brut (part de leurs jours de production respectifs) sur une période, puis se le
# répartissent selon une clé (poids). Cas concret : Romane (mardi) et Stéphanie
# (vendredi) additionnent leurs jours du mois et se partagent 50/50, même si
# l'une est absente. Un artisan hors partenariat garde son revenu brut tel quel
# (ex. Claire, remplaçante à 100 %).
#
# La mise en commun est appliquée au moment du RAPPORT (BakerRevenueService), pas
# stockée. Le revenu brut par jour continue d'utiliser la part littérale
# historisée de l'artisan (ArtisanRevenueShare) ; le partenariat ne fait que
# regrouper et redistribuer ces montants bruts.
class CreateRevenuePartnerships < ActiveRecord::Migration[8.0]
  def change
    create_table :revenue_partnerships do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    create_table :revenue_partnership_memberships do |t|
      t.references :revenue_partnership, null: false, foreign_key: true
      t.references :artisan, null: false, foreign_key: true, index: false
      # Poids de répartition dans la mise en commun (1 = parts égales par défaut ;
      # permet un partage pondéré 60/40 à l'avenir sans changer le moteur).
      t.decimal :weight, precision: 8, scale: 3, null: false, default: 1

      t.timestamps
    end

    # Un artisan appartient à AU PLUS un partenariat (couche de règlement unique).
    add_index :revenue_partnership_memberships, :artisan_id,
              unique: true, name: "index_partnership_memberships_on_artisan_uniqueness"
  end
end
