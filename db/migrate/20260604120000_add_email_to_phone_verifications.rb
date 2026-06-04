class AddEmailToPhoneVerifications < ActiveRecord::Migration[8.0]
  def change
    add_column :phone_verifications, :email, :string
    add_index :phone_verifications, :email

    # The OTP can now be keyed by an email address instead of a phone number
    # (login by email at parity with SMS), so phone_e164 is no longer mandatory.
    change_column_null :phone_verifications, :phone_e164, true
  end
end
