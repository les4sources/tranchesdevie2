class AddPositionToProductImages < ActiveRecord::Migration[8.0]
  def up
    add_column :product_images, :position, :integer
    
    # Initialize positions for existing images grouped by variant
    # Use SQL directly to avoid model loading issues
    execute <<-SQL
      WITH ordered_images AS (
        SELECT id, product_variant_id,
               ROW_NUMBER() OVER (PARTITION BY product_variant_id ORDER BY created_at) as rn
        FROM product_images
      )
      UPDATE product_images
      SET position = ordered_images.rn
      FROM ordered_images
      WHERE product_images.id = ordered_images.id
    SQL
    
    # Add index for better query performance
    add_index :product_images, [:product_variant_id, :position], name: 'index_product_images_on_variant_and_position'
  end

  def down
    remove_index :product_images, name: 'index_product_images_on_variant_and_position'
    remove_column :product_images, :position
  end
end
