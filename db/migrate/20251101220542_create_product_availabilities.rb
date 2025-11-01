class CreateProductAvailabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :product_availabilities do |t|
      t.references :product_variant, null: false, foreign_key: true, index: true
      t.date :start_on, null: false
      t.date :end_on

      t.timestamps
    end

    add_index :product_availabilities, [:start_on, :end_on]
  end
end
