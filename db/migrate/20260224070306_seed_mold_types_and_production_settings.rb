# frozen_string_literal: true

class SeedMoldTypesAndProductionSettings < ActiveRecord::Migration[8.0]
  def up
    now = Time.current

    # Create initial MoldType records
    mold_types = [
      [1, "Grand", 95],
      [2, "Classique", 100],
      [3, "Petit", 50],
      [4, "Grand rond", 10],
      [5, "Classique rond", 10]
    ]

    mold_types.each do |position, name, limit|
      execute(<<-SQL.squish)
        INSERT INTO mold_types (name, "limit", position, created_at, updated_at)
        VALUES ('#{name}', #{limit}, #{position}, '#{now}', '#{now}')
      SQL
    end

    # Create singleton ProductionSetting
    execute(<<-SQL.squish)
      INSERT INTO production_settings (oven_capacity_grams, market_day_oven_capacity_grams, created_at, updated_at)
      VALUES (110000, 165000, '#{now}', '#{now}')
    SQL

    # Set kneader_limit_grams on Froment flour
    execute(<<-SQL.squish)
      UPDATE flours SET kneader_limit_grams = 90000
      WHERE name = 'Froment' AND deleted_at IS NULL
    SQL

    # Backfill mold_type_id on existing breads variants
    # Match the same logic as BakeDayDashboard#detect_mold_size
    #
    # XXL patterns -> no standard mold type (these are special, skip for now)
    #
    # Large (1kg) patterns -> "Grand"
    execute(<<-SQL.squish)
      UPDATE product_variants
      SET mold_type_id = (SELECT id FROM mold_types WHERE name = 'Grand' LIMIT 1)
      WHERE id IN (
        SELECT pv.id FROM product_variants pv
        JOIN products p ON p.id = pv.product_id
        WHERE p.category = 0
          AND pv.mold_type_id IS NULL
          AND (
            LOWER(p.name || ' ' || pv.name) ~ '1\\s?kg'
            OR LOWER(p.name || ' ' || pv.name) ~ '1000'
            OR LOWER(p.name || ' ' || pv.name) ~ 'grand'
          )
      )
    SQL

    # Middle (800g) patterns -> "Classique"
    execute(<<-SQL.squish)
      UPDATE product_variants
      SET mold_type_id = (SELECT id FROM mold_types WHERE name = 'Classique' LIMIT 1)
      WHERE id IN (
        SELECT pv.id FROM product_variants pv
        JOIN products p ON p.id = pv.product_id
        WHERE p.category = 0
          AND pv.mold_type_id IS NULL
          AND (
            LOWER(p.name || ' ' || pv.name) ~ '800\\s?g'
            OR LOWER(p.name || ' ' || pv.name) ~ '0\\.8'
            OR LOWER(p.name || ' ' || pv.name) ~ '800'
            OR LOWER(p.name || ' ' || pv.name) ~ 'moyen'
          )
      )
    SQL

    # Small (600g) patterns -> "Petit"
    execute(<<-SQL.squish)
      UPDATE product_variants
      SET mold_type_id = (SELECT id FROM mold_types WHERE name = 'Petit' LIMIT 1)
      WHERE id IN (
        SELECT pv.id FROM product_variants pv
        JOIN products p ON p.id = pv.product_id
        WHERE p.category = 0
          AND pv.mold_type_id IS NULL
          AND (
            LOWER(p.name || ' ' || pv.name) ~ '600\\s?g'
            OR LOWER(p.name || ' ' || pv.name) ~ '0\\.6'
            OR LOWER(p.name || ' ' || pv.name) ~ '600'
            OR LOWER(p.name || ' ' || pv.name) ~ 'petit'
          )
      )
    SQL
  end

  def down
    execute("DELETE FROM mold_types")
    execute("DELETE FROM production_settings")
    execute("UPDATE flours SET kneader_limit_grams = NULL")
    execute("UPDATE product_variants SET mold_type_id = NULL")
  end
end
