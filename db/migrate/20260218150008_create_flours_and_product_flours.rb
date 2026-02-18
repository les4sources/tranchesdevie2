# frozen_string_literal: true

class CreateFloursAndProductFlours < ActiveRecord::Migration[8.0]
  def up
    create_table :flours do |t|
      t.string :name, null: false
      t.integer :position, default: 0
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :flours, :deleted_at
    add_index :flours, :name, unique: true, where: "(deleted_at IS NULL)"

    create_table :product_flours do |t|
      t.references :product, null: false, foreign_key: true
      t.references :flour, null: false, foreign_key: true
      t.integer :percentage, null: false
      t.timestamps
    end
    add_index :product_flours, [:product_id, :flour_id], unique: true

    # Seed flours matching current product.flour values
    flour_names = [
      [1, "Froment"],      # wheat
      [2, "Épeautre"],    # spelled
      [3, "Petit épeautre"], # small_spelled
      [4, "Blé ancien"]   # ancien_wheat
    ]
    now = Time.current
    flour_names.each do |position, name|
      execute(<<-SQL.squish)
        INSERT INTO flours (name, position, created_at, updated_at)
        VALUES ('#{name.gsub("'", "''")}', #{position}, '#{now}', '#{now}')
      SQL
    end

    # Migrate existing product.flour to product_flours (100% for each)
    flour_code_to_id = {}
    %w[wheat spelled small_spelled ancien_wheat].each_with_index do |code, i|
      name = flour_names[i][1]
      id_row = connection.select_one("SELECT id FROM flours WHERE name = '#{name.gsub("'", "''")}' LIMIT 1")
      flour_code_to_id[code] = id_row["id"].to_i if id_row
    end

    rows = connection.select_all("SELECT id, flour FROM products WHERE flour IS NOT NULL AND flour != ''")
    rows.each do |row|
      product_id = row["id"]
      flour_id = flour_code_to_id[row["flour"]]
      next unless flour_id

      execute(<<-SQL.squish)
        INSERT INTO product_flours (product_id, flour_id, percentage, created_at, updated_at)
        VALUES (#{product_id}, #{flour_id}, 100, '#{now}', '#{now}')
      SQL
    end
  end

  def down
    drop_table :product_flours
    drop_table :flours
  end
end
