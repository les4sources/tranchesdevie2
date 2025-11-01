class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_payment_intent_id, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :payments, :stripe_payment_intent_id, unique: true
    add_index :payments, :status
  end
end
