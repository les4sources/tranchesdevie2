class CreateBakeDays < ActiveRecord::Migration[8.0]
  def change
    create_table :bake_days do |t|
      t.date :baked_on, null: false
      t.timestamptz :cut_off_at, null: false

      t.timestamps
    end

    add_index :bake_days, :baked_on, unique: true
  end
end
