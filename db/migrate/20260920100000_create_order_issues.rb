# Signalement d'un problème au retrait (#remboursement-partiel).
#
# Le client constate en rentrant chez lui qu'il manque un pain, ou qu'on lui en
# a donné un autre. Jusqu'ici il n'avait aucun canal dans l'app : il devait
# attraper un boulanger. Le signalement est une DEMANDE, jamais un
# remboursement — un humain décide toujours de ce qu'il rembourse.
class CreateOrderIssues < ActiveRecord::Migration[8.0]
  def change
    create_table :order_issues do |t|
      t.references :order, null: false, foreign_key: true
      # Dénormalisé depuis la commande : les écrans d'admin listent des
      # signalements sans avoir à joindre les commandes pour nommer le client.
      t.references :customer, null: false, foreign_key: true

      t.text :description, null: false
      t.integer :state, null: false, default: 0
      t.datetime :resolved_at
      t.string :resolved_by
      t.timestamps
    end

    add_index :order_issues, :state

    # Lignes concernées, telles que le client les a cochées. Facultatives : un
    # problème peut ne porter sur aucune ligne précise (« le pain était cru »).
    create_table :order_issue_items do |t|
      t.references :order_issue, null: false, foreign_key: true
      t.references :order_item, null: false, foreign_key: true
      t.integer :qty, null: false, default: 1
      t.timestamps
    end
  end
end
