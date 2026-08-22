class CreateProductImages < ActiveRecord::Migration[8.0]
  def change
    create_table :product_images do |t|
      t.references :product, null: false, foreign_key: true
      t.references :product_variant, null: true, foreign_key: true

      t.timestamps
    end
  end
end
