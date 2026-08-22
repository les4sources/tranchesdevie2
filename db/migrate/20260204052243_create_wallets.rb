class CreateWallets < ActiveRecord::Migration[8.0]
  def change
    create_table :wallets do |t|
      t.references :customer, null: false, foreign_key: true, index: { unique: true }
      t.integer :balance_cents, null: false, default: 0
      t.integer :low_balance_threshold_cents, null: false, default: 1000

      t.timestamps
    end
  end
end
