class MakePhoneE164NullableInCustomers < ActiveRecord::Migration[8.0]
  def change
    change_column_null :customers, :phone_e164, true
    # Remove the unique index and recreate it to allow multiple nulls
    remove_index :customers, :phone_e164
    add_index :customers, :phone_e164, unique: true, where: "phone_e164 IS NOT NULL"
  end
end
