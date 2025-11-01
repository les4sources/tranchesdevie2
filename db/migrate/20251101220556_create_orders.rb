class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.references :customer, null: false, foreign_key: true, index: true
      t.references :bake_day, null: false, foreign_key: true, index: true
      t.integer :status, null: false, default: 0
      t.integer :total_cents, null: false
      t.string :public_token, null: false, limit: 24
      t.string :order_number, null: false
      t.string :payment_intent_id

      t.timestamps
    end

    add_index :orders, :public_token, unique: true
    add_index :orders, :order_number
    add_index :orders, :status
    add_index :orders, :payment_intent_id, unique: true, where: "payment_intent_id IS NOT NULL"
  end
end
