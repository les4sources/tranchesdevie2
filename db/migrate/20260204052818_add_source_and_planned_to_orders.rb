class AddSourceAndPlannedToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :source, :integer, null: false, default: 0
    add_index :orders, :source
  end
end
