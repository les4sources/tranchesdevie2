# Clients facturables livrés par la boulangerie (retour Michael 06/10/2026) :
# eux seuls reçoivent un bon de livraison. Faux par défaut.
class AddDeliveredByBakeryToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :delivered_by_bakery, :boolean, default: false, null: false
  end
end
