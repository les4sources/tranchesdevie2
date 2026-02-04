class CreateWalletTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :wallet_transactions do |t|
      t.references :wallet, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.integer :transaction_type, null: false
      t.references :order, foreign_key: true  # optional, only for order-related transactions
      t.string :stripe_payment_intent_id
      t.text :description

      t.timestamps
    end

    add_index :wallet_transactions, :created_at
  end
end
