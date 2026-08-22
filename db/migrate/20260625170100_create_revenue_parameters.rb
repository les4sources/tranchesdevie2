class CreateRevenueParameters < ActiveRecord::Migration[8.0]
  def change
    # Paramètres généraux du calcul des revenus boulangers (#54), historisés par
    # date d'activation (même patron que BreadBagPrice #52). Deux clés :
    #   - "transport"         : coût de transport par jour de production, en cents
    #                           (référence : 15 €/jour = 1500).
    #   - "four_sources_rate" : taux de prélèvement des 4 Sources sur la marge
    #                           brute, en points de base (référence : 30 % = 3000).
    # `value` est un entier (cents ou points de base selon la clé) pour rester
    # cohérent avec la convention "tout en entier" du projet. La valeur applicable
    # à une date est le palier le plus récent dont `active_from` <= date.
    create_table :revenue_parameters do |t|
      t.string :key, null: false
      t.integer :value, null: false
      t.date :active_from, null: false

      t.timestamps
    end

    add_index :revenue_parameters, [ :key, :active_from ]
  end
end
