class AddActiveToPickupLocations < ActiveRecord::Migration[8.0]
  def change
    # Désactivation d'un point de retrait (#199) : distincte du soft delete.
    # Un lieu inactif disparaît des choix du client mais reste entier dans
    # l'historique — c'est exactement ce que la suppression ne permettait pas.
    # `default: true` : tous les lieux existants restent actifs.
    add_column :pickup_locations, :active, :boolean, default: true, null: false
  end
end
