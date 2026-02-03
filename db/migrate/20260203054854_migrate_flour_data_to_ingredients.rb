class MigrateFlourDataToIngredients < ActiveRecord::Migration[8.0]
  def up
    flour_mapping = {
      "wheat" => "Farine de froment",
      "spelled" => "Farine d'épeautre",
      "ancien_wheat" => "Farine de blé ancien"
    }

    flour_ids = {}
    now = Time.current

    flour_mapping.each_with_index do |(key, name), index|
      escaped_name = name.gsub("'", "''")
      result = execute(<<-SQL.squish)
        INSERT INTO ingredients (name, unit_type, position, created_at, updated_at)
        VALUES ('#{escaped_name}', 0, #{index + 1}, '#{now}', '#{now}')
        RETURNING id
      SQL
      flour_ids[key] = result.first["id"]
    end

    # Migrate existing flour_quantity data from variants
    variants_with_flour = execute(<<-SQL.squish)
      SELECT pv.id AS variant_id, pv.flour_quantity, p.flour
      FROM product_variants pv
      JOIN products p ON p.id = pv.product_id
      WHERE pv.flour_quantity IS NOT NULL
        AND pv.flour_quantity > 0
        AND p.flour IS NOT NULL
        AND p.flour != ''
    SQL

    variants_with_flour.each do |row|
      variant_id = row["variant_id"]
      flour_quantity = row["flour_quantity"]
      flour_type = row["flour"]

      ingredient_id = flour_ids[flour_type]
      next unless ingredient_id

      execute(<<-SQL.squish)
        INSERT INTO variant_ingredients (product_variant_id, ingredient_id, quantity, created_at, updated_at)
        VALUES (#{variant_id}, #{ingredient_id}, #{flour_quantity}, '#{now}', '#{now}')
      SQL
    end
  end

  def down
    execute("DELETE FROM variant_ingredients")
    execute("DELETE FROM ingredients WHERE name IN ('Farine de froment', 'Farine d''épeautre', 'Farine de blé ancien')")
  end
end
