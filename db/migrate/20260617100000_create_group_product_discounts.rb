class CreateGroupProductDiscounts < ActiveRecord::Migration[8.0]
  def change
    create_table :group_product_discounts do |t|
      t.references :group, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.references :product_variant, null: true, foreign_key: true
      # "percent" : discount_value = pourcentage (0-100)
      # "fixed"   : discount_value = réduction en cents par rapport au prix public
      t.string :discount_kind, null: false, default: "percent"
      t.integer :discount_value, null: false, default: 0

      t.timestamps
    end

    # Une seule remise ciblée par (groupe, produit) au niveau produit…
    add_index :group_product_discounts, [ :group_id, :product_id ],
              unique: true, where: "product_variant_id IS NULL",
              name: "index_gpd_unique_group_product"
    # …et une seule par (groupe, variante) au niveau variante.
    add_index :group_product_discounts, [ :group_id, :product_variant_id ],
              unique: true, where: "product_variant_id IS NOT NULL",
              name: "index_gpd_unique_group_variant"
  end
end
