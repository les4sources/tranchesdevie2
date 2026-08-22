# frozen_string_literal: true

class CreateBakeDayArtisans < ActiveRecord::Migration[8.0]
  def change
    create_table :bake_day_artisans do |t|
      t.references :bake_day, null: false, foreign_key: true
      t.references :artisan, null: false, foreign_key: true

      t.timestamps
    end

    add_index :bake_day_artisans, %i[bake_day_id artisan_id], unique: true
  end
end
