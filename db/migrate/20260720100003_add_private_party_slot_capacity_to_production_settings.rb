class AddPrivatePartySlotCapacityToProductionSettings < ActiveRecord::Migration[8.0]
  # Capacité par créneau des parties PRIVÉES (#pizza-parties) : nombre max de
  # parties privées réservables sur un même (date, créneau midi/soir).
  def change
    add_column :production_settings, :private_party_slot_capacity, :integer, null: false, default: 2
  end
end
