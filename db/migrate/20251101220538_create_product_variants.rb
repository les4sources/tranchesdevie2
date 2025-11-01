class CreateProductVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variants do |t|
      t.references :product, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.integer :price_cents, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
