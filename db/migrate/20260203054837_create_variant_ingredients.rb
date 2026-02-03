class CreateVariantIngredients < ActiveRecord::Migration[8.0]
  def change
    create_table :variant_ingredients do |t|
      t.references :product_variant, null: false, foreign_key: true
      t.references :ingredient, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :variant_ingredients, [:product_variant_id, :ingredient_id],
              unique: true,
              name: "index_variant_ingredients_on_variant_and_ingredient"
  end
end
