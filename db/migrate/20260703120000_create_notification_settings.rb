class CreateNotificationSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_settings do |t|
      t.text :ready_sms_body
      t.text :ready_sms_body_unpaid
      t.string :ready_email_subject

      t.timestamps
    end
  end
end
