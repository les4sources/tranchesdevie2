class AddCancelledByToOrders < ActiveRecord::Migration[8.0]
  def change
    # Qui a annulé une Pizza party payée (#pizza-parties) : le client depuis sa
    # page de suivi, ou la boulangerie. Les deux donnent le même état technique
    # (commande annulée, paiement remboursé) mais ne se racontent pas pareil au
    # client — « tu as annulé » n'est pas « nous avons dû annuler ».
    add_column :orders, :cancelled_by, :string
  end
end
