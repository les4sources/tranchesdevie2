class CreateProductPickupLocationExclusions < ActiveRecord::Migration[8.0]
  # Exclusion produit ↔ lieu de retrait (#152) : la présence d'une ligne signifie
  # que ce produit N'EST PAS commandable pour ce lieu de retrait. Concept au
  # niveau PRODUIT (pas variante) et indépendant de la fournée. À ne pas
  # confondre avec `variant_group_restrictions` (restriction par groupe client).
  def change
    create_table :product_pickup_location_exclusions do |t|
      t.references :product, null: false, foreign_key: true
      t.references :pickup_location, null: false, foreign_key: true

      t.timestamps
    end

    add_index :product_pickup_location_exclusions, [ :product_id, :pickup_location_id ],
      unique: true, name: "index_product_pickup_exclusions_on_pair"
  end
end
