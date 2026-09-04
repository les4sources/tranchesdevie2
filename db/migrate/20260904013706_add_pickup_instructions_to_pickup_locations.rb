# frozen_string_literal: true

# « Quand venir chercher sa commande » (#252) — distinct de `description`, qui
# répond à « c'est où ? » au moment du choix. Naît NULL partout : la phrase est
# propre à chaque lieu, ce sont les boulangers qui l'écrivent.
class AddPickupInstructionsToPickupLocations < ActiveRecord::Migration[8.0]
  def change
    add_column :pickup_locations, :pickup_instructions, :text
  end
end
