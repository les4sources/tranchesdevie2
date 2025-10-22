class CreateStripeEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :stripe_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.timestamp :processed_at
      t.jsonb :payload
      t.references :tenant, foreign_key: true

      t.timestamps
    end

    add_index :stripe_events, :event_id, unique: true
    add_index :stripe_events, :event_type
  end
end
