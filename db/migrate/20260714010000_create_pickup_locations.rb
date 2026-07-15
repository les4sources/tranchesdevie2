class CreatePickupLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :pickup_locations do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :default, null: false, default: false
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :pickup_locations, :deleted_at
    # Un seul lieu par défaut à la fois (les lieux supprimés ne comptent pas).
    add_index :pickup_locations, :default, unique: true,
      where: "\"default\" = true AND deleted_at IS NULL",
      name: "index_pickup_locations_on_single_default"

    create_table :bake_day_pickup_locations do |t|
      t.references :bake_day, null: false, foreign_key: true
      t.references :pickup_location, null: false, foreign_key: true

      t.timestamps
    end

    add_index :bake_day_pickup_locations, [ :bake_day_id, :pickup_location_id ],
      unique: true, name: "index_bake_day_pickup_locations_on_pair"
  end
end
