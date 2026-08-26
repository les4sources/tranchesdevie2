class CreateHistorisedKiloPrices < ActiveRecord::Migration[8.0]
  def up
    # Prix au kilo historisés par date d'effet (#209).
    #
    # « Est-ce qu'il n'y aurait pas moyen que, au moment où on change le prix,
    # le reporting d'avant tienne compte du prix d'avant […] le reporting ne
    # devrait jamais changer. » Même patron que `variant_cost_prices` et
    # `revenue_parameters` : on n'écrase jamais un prix, on ajoute un palier.
    create_table :ingredient_prices do |t|
      t.references :ingredient, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date :active_from, null: false

      t.timestamps
    end

    add_index :ingredient_prices, [ :ingredient_id, :active_from ]

    create_table :flour_prices do |t|
      t.references :flour, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date :active_from, null: false

      t.timestamps
    end

    add_index :flour_prices, [ :flour_id, :active_from ]

    # Reprise du prix unique déjà saisi sur chaque farine : il devient le
    # premier palier, daté assez tôt pour couvrir tout l'historique existant.
    # Sans ça, la bascule vers l'historique ferait disparaître ces prix.
    execute <<~SQL.squish
      INSERT INTO flour_prices (flour_id, amount_cents, active_from, created_at, updated_at)
      SELECT id, price_per_kg_cents, DATE '2020-01-01', NOW(), NOW()
      FROM flours
      WHERE price_per_kg_cents IS NOT NULL
    SQL
  end

  def down
    drop_table :flour_prices
    drop_table :ingredient_prices
  end
end
