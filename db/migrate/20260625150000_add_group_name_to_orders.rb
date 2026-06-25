class AddGroupNameToOrders < ActiveRecord::Migration[8.0]
  def change
    # Nom libre du groupe « 4 Sources » pour lequel la commande est passée (#99).
    # Stocké sur la commande (pas sur le client) : un même client peut commander
    # pour des groupes différents. Nullable : la plupart des commandes n'en ont pas.
    add_column :orders, :group_name, :string
  end
end
