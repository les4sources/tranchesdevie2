class CreatePartyEvents < ActiveRecord::Migration[8.0]
  # Événements party (#pizza-parties) : datés, indépendants des fournées.
  # kind = 0 publique (organisée par la boulangerie, inscriptions adulte/enfant)
  #      / 1 privée (réservée par un client pour un créneau midi/soir).
  # slot = 0 midi / 1 soir (requis en privé). capacity nul = illimité.
  def change
    create_table :party_events do |t|
      t.integer :kind, null: false
      t.date :held_on, null: false
      t.integer :slot
      t.integer :capacity
      t.string :title
      t.text :description
      t.datetime :registration_closes_at
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :party_events, :held_on
    add_index :party_events, [ :kind, :held_on ]
    add_index :party_events, :deleted_at
  end
end
