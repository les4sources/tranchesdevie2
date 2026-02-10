# frozen_string_literal: true

class CreateArtisans < ActiveRecord::Migration[8.0]
  def change
    create_table :artisans do |t|
      t.string :name, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
