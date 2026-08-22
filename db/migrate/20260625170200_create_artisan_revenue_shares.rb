class CreateArtisanRevenueShares < ActiveRecord::Migration[8.0]
  def change
    # Part de revenu d'un artisan dans le pool boulangers, historisée par date
    # d'activation (#54), sur le même patron que VariantCostPrice (#90) /
    # BreadBagPrice (#52). La part applicable à une date donnée est le palier le
    # plus récent dont `active_from` est antérieure ou égale à la date. Aucune
    # valeur par défaut : la part est saisie en admin (décision Michael 25/06).
    # `percent` est un pourcentage littéral (ex. 50.0 = 50 %), non normalisé.
    create_table :artisan_revenue_shares do |t|
      t.references :artisan, null: false, foreign_key: true
      t.decimal :percent, precision: 6, scale: 3, null: false
      t.date :active_from, null: false

      t.timestamps
    end

    add_index :artisan_revenue_shares, [ :artisan_id, :active_from ]
  end
end
