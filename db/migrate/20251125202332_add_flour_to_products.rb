class AddFlourToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :flour, :string
  end
end
