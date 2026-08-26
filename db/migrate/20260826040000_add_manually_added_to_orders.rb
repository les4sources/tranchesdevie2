class AddManuallyAddedToOrders < ActiveRecord::Migration[8.0]
  def change
    # Inscription ajoutée à la main par l'équipe (#203) : sur place, ou parce
    # que quelqu'un a demandé directement aux boulangers. Elle est en tout point
    # une commande party normale — c'est le but, pour que les revenus la
    # traitent à l'identique — ce drapeau ne sert QU'À la distinguer à l'écran.
    #
    # La garde vaut pour l'ordre de fusion : #204 ajoute la même colonne pour
    # les parties privées, depuis une branche parallèle issue de `main`.
    return if column_exists?(:orders, :manually_added)

    add_column :orders, :manually_added, :boolean, default: false, null: false
  end
end
