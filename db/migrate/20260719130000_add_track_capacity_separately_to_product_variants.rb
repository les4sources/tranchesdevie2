class AddTrackCapacitySeparatelyToProductVariants < ActiveRecord::Migration[8.0]
  # Marqueur explicite (#151) : une variante « comptée séparément » reste comptée
  # dans la capacité de son moule, mais son décompte apparaît à part dans le bloc
  # « Moules » du planning. Remplace toute détection par nom dans la LOGIQUE de
  # capacité (le nom ne sert qu'au backfill initial ci-dessous, une seule fois).
  def up
    add_column :product_variants, :track_capacity_separately, :boolean, null: false, default: false

    # Backfill initial : les variantes XXL de PAIN (froment 1,4 kg) sont cuites
    # dans le grand moule mais doivent être décomptées à part. On les marque et,
    # si elles n'ont pas encore de moule, on les rattache au moule « Grand ».
    # Idempotent et défensif : ne touche que les pains dont le libellé contient
    # « xxl », n'écrase pas un moule déjà assigné. Même approche de backfill par
    # libellé que la migration seed des moules (20260224070306).
    execute(<<-SQL.squish)
      UPDATE product_variants
      SET track_capacity_separately = true,
          mold_type_id = COALESCE(
            mold_type_id,
            (SELECT id FROM mold_types WHERE name = 'Grand' AND deleted_at IS NULL LIMIT 1)
          )
      WHERE id IN (
        SELECT pv.id FROM product_variants pv
        JOIN products p ON p.id = pv.product_id
        WHERE p.category = 0
          AND LOWER(p.name || ' ' || pv.name) ~ 'xxl'
      )
    SQL
  end

  def down
    remove_column :product_variants, :track_capacity_separately
  end
end
