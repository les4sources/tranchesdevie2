class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.text :description
      t.integer :category, null: false, default: 0
      t.integer :position, default: 0
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :products, :category
    add_index :products, [:category, :position, :name]
  end
end
