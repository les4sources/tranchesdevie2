class CreatePhoneVerifications < ActiveRecord::Migration[8.0]
  def change
    create_table :phone_verifications do |t|
      t.string :phone_e164, null: false
      t.string :code, null: false, limit: 6
      t.datetime :expires_at, null: false
      t.integer :attempts_count, default: 0, null: false

      t.timestamps
    end

    add_index :phone_verifications, :phone_e164
    add_index :phone_verifications, :code
  end
end
