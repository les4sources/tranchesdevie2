# frozen_string_literal: true

class CreateDoughRatios < ActiveRecord::Migration[8.0]
  def up
    create_table :dough_ratios do |t|
      t.string :key, null: false
      t.decimal :value, precision: 10, scale: 5, null: false
      t.string :label, null: false
      t.integer :position, default: 0
      t.timestamps
    end

    add_index :dough_ratios, :key, unique: true

    # Seed the 4 default baking ratios
    [
      { key: "farine", value: 0.5556, label: "Farine (ratio pâte)", position: 1 },
      { key: "sel", value: 0.022, label: "Sel (ratio farine)", position: 2 },
      { key: "eau", value: 0.655, label: "Eau (ratio farine)", position: 3 },
      { key: "levain", value: 0.12095, label: "Levain (ratio pâte)", position: 4 }
    ].each do |ratio|
      DoughRatio.create!(ratio)
    end
  end

  def down
    drop_table :dough_ratios
  end
end
