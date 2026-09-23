# Ouvertures exceptionnelles des parties PRIVÉES (#pizza-parties).
#
# Symétrique de `party_slot_blocks` : le blocage FERME un soir ouvert par la
# règle (mardi/vendredi), l'ouverture OUVRE un soir que la règle ignore.
class CreatePartyOpenings < ActiveRecord::Migration[8.0]
  def change
    create_table :party_openings do |t|
      t.date :opened_on, null: false
      t.string :reason

      t.timestamps
    end

    add_index :party_openings, :opened_on, unique: true
  end
end
