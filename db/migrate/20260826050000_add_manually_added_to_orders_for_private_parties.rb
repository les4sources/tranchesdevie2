class AddManuallyAddedToOrdersForPrivateParties < ActiveRecord::Migration[8.0]
  def change
    # Drapeau « ajoutée à la main » sur une commande (#203 pour les inscriptions
    # publiques, #204 pour les parties privées). Les deux branches partent de
    # `main` et ajoutent la même colonne : la garde rend la migration sûre quel
    # que soit l'ordre de fusion.
    return if column_exists?(:orders, :manually_added)

    add_column :orders, :manually_added, :boolean, default: false, null: false
  end
end
