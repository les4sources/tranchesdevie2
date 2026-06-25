class CreateVariantCostPrices < ActiveRecord::Migration[8.0]
  def change
    create_table :variant_cost_prices do |t|
      t.references :product_variant, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date :active_from, null: false

      t.timestamps
    end

    # Recherche du palier applicable à une date : on filtre sur active_from puis
    # on prend le plus récent.
    add_index :variant_cost_prices, [ :product_variant_id, :active_from ]
  end
end
