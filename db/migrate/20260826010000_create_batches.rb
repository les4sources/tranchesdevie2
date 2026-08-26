class CreateBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :batches do |t|
      t.references :bake_day, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :batches, [ :bake_day_id, :position ]

    # Affectation d'une ligne de commande à une fournée (#194). Nullable par
    # design : une ligne non affectée est un état normal et visible, pas une
    # anomalie — c'est ce qui empêche d'« oublier » un pain.
    add_reference :order_items, :batch, null: true, foreign_key: true
  end
end
