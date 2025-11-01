class CreateSmsMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :sms_messages do |t|
      t.integer :direction, null: false, default: 0
      t.string :to_e164, null: false
      t.string :from_e164, null: false
      t.date :baked_on
      t.text :body, null: false
      t.integer :kind, null: false, default: 0
      t.string :external_id

      t.timestamps
    end

    add_index :sms_messages, :to_e164
    add_index :sms_messages, :direction
    add_index :sms_messages, :kind
    add_index :sms_messages, :external_id
  end
end
