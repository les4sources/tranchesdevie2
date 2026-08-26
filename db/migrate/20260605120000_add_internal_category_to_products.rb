class AddInternalCategoryToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :internal_category, :integer, default: 0, null: false
    add_index :products, :internal_category
  end
end
