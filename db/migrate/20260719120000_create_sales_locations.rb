class CreateSalesLocations < ActiveRecord::Migration[8.0]
  def change
    # Lieu de vente (#150) : un endroit où la boulangerie vend (ex. un marché),
    # porteur d'un COÛT (emplacement / stand) déductible du bénéfice. Concept
    # SÉPARÉ du lieu de retrait (`PickupLocation`) — décision produit. Soft
    # delete comme MoldType / PickupLocation : un lieu retiré disparaît des
    # sélecteurs mais reste lisible sur les fournées passées qui le référencent.
    create_table :sales_locations do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :sales_locations, :deleted_at
    add_index :sales_locations, :name, unique: true,
      where: "deleted_at IS NULL", name: "index_sales_locations_on_name_unique"

    # Coût du lieu de vente historisé par période de validité (#150). Même esprit
    # que les coûts historisés existants (VariantCostPrice, BreadBagPrice,
    # RevenueParameter), mais avec une borne de fin explicite : `valid_until` nul
    # = période en cours. Le coût applicable à une date est la période qui la
    # couvre (`valid_from <= date <= valid_until`, ou `valid_until` nul).
    create_table :sales_location_costs do |t|
      t.references :sales_location, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date :valid_from, null: false
      t.date :valid_until

      t.timestamps
    end

    add_index :sales_location_costs, [ :sales_location_id, :valid_from ]

    # Un jour de cuisson peut être lié à 0..N lieux de vente (#150) : le coût
    # du/des lieu(x) est déduit de la marge brute avant le partage 70/30.
    create_table :bake_day_sales_locations do |t|
      t.references :bake_day, null: false, foreign_key: true
      t.references :sales_location, null: false, foreign_key: true

      t.timestamps
    end

    add_index :bake_day_sales_locations, [ :bake_day_id, :sales_location_id ],
      unique: true, name: "index_bake_day_sales_locations_on_pair"
  end
end
