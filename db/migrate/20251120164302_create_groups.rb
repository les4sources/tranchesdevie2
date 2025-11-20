class CreateGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :groups do |t|
      t.string :name, null: false
      t.integer :discount_percent, null: false

      t.timestamps
    end
  end
end
