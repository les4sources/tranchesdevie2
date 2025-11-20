class AddGroupIdToCustomers < ActiveRecord::Migration[8.0]
  def change
    add_reference :customers, :group, null: true, foreign_key: true
  end
end
