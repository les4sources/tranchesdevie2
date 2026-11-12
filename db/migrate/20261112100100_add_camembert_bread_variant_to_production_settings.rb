# Pain fourni aux Camembert Parties (#camembert-parties) : le grand froment 1 kg.
# Réglable, pour qu'un renommage de variante ne casse pas le calcul en silence.
class AddCamembertBreadVariantToProductionSettings < ActiveRecord::Migration[8.1]
  def up
    add_reference :production_settings, :camembert_bread_variant,
                  foreign_key: { to_table: :product_variants }, null: true

    execute <<~SQL.squish
      UPDATE production_settings
      SET camembert_bread_variant_id = (
        SELECT product_variants.id FROM product_variants
        JOIN products ON products.id = product_variants.product_id
        WHERE products.name = 'Pain au froment' AND product_variants.name = 'Grand 1 kg'
        ORDER BY product_variants.id LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :production_settings, :camembert_bread_variant, foreign_key: { to_table: :product_variants }
  end
end
