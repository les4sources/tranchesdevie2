class CreateEmailMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :email_messages do |t|
      t.integer :direction, default: 0, null: false
      t.string :to_email, null: false
      t.string :from_email, null: false
      t.string :subject
      t.text :body_html, null: false
      t.integer :kind, default: 0, null: false
      t.string :message_id
      t.bigint :customer_id
      t.bigint :order_id
      t.datetime :sent_at

      t.timestamps
    end

    add_index :email_messages, :customer_id
    add_index :email_messages, :order_id
    add_index :email_messages, :kind
    add_index :email_messages, :message_id
  end
end
