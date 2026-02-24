# frozen_string_literal: true

class CreateMoldTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :mold_types do |t|
      t.string :name, null: false
      t.integer :limit, null: false
      t.integer :position, default: 0
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :mold_types, :deleted_at
    add_index :mold_types, :name, unique: true, where: "(deleted_at IS NULL)"
  end
end
