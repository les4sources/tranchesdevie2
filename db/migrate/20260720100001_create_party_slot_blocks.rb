class CreatePartySlotBlocks < ActiveRecord::Migration[8.0]
  # Blocages de créneaux party PRIVÉE (#pizza-parties) : le privé est ouvert par
  # défaut ; l'admin bloque des créneaux ici. slot nul = toute la journée bloquée.
  def change
    create_table :party_slot_blocks do |t|
      t.date :blocked_on, null: false
      t.integer :slot
      t.string :reason
      t.timestamps
    end

    add_index :party_slot_blocks, [ :blocked_on, :slot ], unique: true
  end
end
