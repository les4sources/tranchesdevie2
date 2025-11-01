class CreateOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true, index: true
      t.references :product_variant, null: false, foreign_key: true, index: true
      t.integer :qty, null: false
      t.integer :unit_price_cents, null: false

      t.timestamps
    end
  end
end
