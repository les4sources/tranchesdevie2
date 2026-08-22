class AddEmailOptOutToCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :email_opt_out, :boolean, default: false, null: false
  end
end
