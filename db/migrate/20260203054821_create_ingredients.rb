class CreateIngredients < ActiveRecord::Migration[8.0]
  def change
    create_table :ingredients do |t|
      t.string :name, null: false
      t.integer :unit_type, default: 0, null: false
      t.integer :position, default: 0
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :ingredients, :name, unique: true, where: "deleted_at IS NULL"
    add_index :ingredients, :deleted_at
  end
end
