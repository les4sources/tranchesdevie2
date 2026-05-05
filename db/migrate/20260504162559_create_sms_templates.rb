class CreateSmsTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :sms_templates do |t|
      t.string :name, null: false
      t.string :external_id
      t.string :category, null: false
      t.string :language, null: false, default: "fr"
      t.text :body, null: false
      t.jsonb :variables, null: false, default: []
      t.datetime :synced_at

      t.timestamps
    end

    add_index :sms_templates, :name, unique: true
    add_index :sms_templates, :external_id
  end
end
