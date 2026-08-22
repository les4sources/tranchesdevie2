class AddFlourQuantityToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :flour_quantity, :integer
  end
end
