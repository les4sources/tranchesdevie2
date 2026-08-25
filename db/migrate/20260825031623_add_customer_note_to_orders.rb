class AddCustomerNoteToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :customer_note, :text
  end
end
