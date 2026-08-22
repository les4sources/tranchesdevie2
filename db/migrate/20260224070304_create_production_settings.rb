# frozen_string_literal: true

class CreateProductionSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :production_settings do |t|
      t.integer :oven_capacity_grams, null: false, default: 110_000
      t.integer :market_day_oven_capacity_grams, null: false, default: 165_000
      t.timestamps
    end
  end
end
