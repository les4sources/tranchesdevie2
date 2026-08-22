class AddPartyEventToOrders < ActiveRecord::Migration[8.0]
  # Une commande party porte sa date d'ÉVÉNEMENT, pas de fournée (#pizza-parties).
  # On rend donc bake_day optionnel et on relie la commande à son party_event.
  # Les commandes pain gardent leur bake_day ; les rapports pain (jointures INNER
  # sur bake_day) excluent naturellement les commandes party.
  def change
    change_column_null :orders, :bake_day_id, true
    add_reference :orders, :party_event, null: true, foreign_key: true
  end
end
