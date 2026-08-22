class AddCustomerIdAndSentAtToSmsMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :sms_messages, :customer, null: true, foreign_key: true
    add_column :sms_messages, :sent_at, :datetime
  end
end
