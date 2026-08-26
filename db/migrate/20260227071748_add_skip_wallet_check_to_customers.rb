class AddSkipWalletCheckToCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :skip_wallet_check, :boolean, default: false, null: false
  end
end
