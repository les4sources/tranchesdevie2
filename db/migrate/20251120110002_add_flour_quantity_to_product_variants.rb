class AddFlourQuantityToProductVariants < ActiveRecord::Migration[8.0]
  def change
    add_column :product_variants, :flour_quantity, :integer
  end
end
