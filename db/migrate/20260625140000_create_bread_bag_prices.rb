class CreateBreadBagPrices < ActiveRecord::Migration[8.0]
  def up
    # Prix d'un sac à pain, paramètre général historisé par date d'activation (#52).
    create_table :bread_bag_prices do |t|
      t.integer :amount_cents, null: false
      t.date :active_from, null: false

      t.timestamps
    end
    add_index :bread_bag_prices, :active_from

    # Valeur de référence (#52) : 0,04 €/sac, active à partir du 01/01/2026.
    execute(<<~SQL.squish)
      INSERT INTO bread_bag_prices (amount_cents, active_from, created_at, updated_at)
      VALUES (4, '2026-01-01', NOW(), NOW())
    SQL
  end

  def down
    drop_table :bread_bag_prices
  end
end
