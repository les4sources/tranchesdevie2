# Remboursement PARTIEL d'une commande livrée (#remboursement-partiel).
#
# Volontairement distinct du remboursement total, qui ne s'enregistre nulle
# part : il se lit sur `payments.status = refunded` (ou une transaction
# `order_refund`) et annule la commande. Un remboursement partiel, lui, ne
# change ni le statut logistique ni le `payment_status` — la commande a bien
# été livrée et encaissée, on en rend un morceau. Il lui faut donc sa propre
# trace, et cette table est la SEULE source de vérité du montant rendu.
class CreatePartialRefunds < ActiveRecord::Migration[8.0]
  def change
    create_table :partial_refunds do |t|
      t.references :order, null: false, foreign_key: true
      # Le signalement auquel ce remboursement répond, s'il y en a un : un
      # boulanger peut aussi rembourser de sa propre initiative.
      t.references :order_issue, foreign_key: true

      t.integer :amount_cents, null: false
      t.integer :channel, null: false
      t.text :reason
      # Traces du mouvement réel, selon le canal.
      t.string :stripe_refund_id
      t.references :wallet_transaction, foreign_key: true
      t.timestamps
    end

    add_index :partial_refunds, :stripe_refund_id, unique: true, where: "stripe_refund_id IS NOT NULL"

    # Ce qui a été remboursé, ligne à ligne. `amount_cents` est le NET de la
    # quantité rendue (remise du client déjà répartie) : figé ici parce que le
    # prix de la variante, lui, bougera.
    create_table :partial_refund_items do |t|
      t.references :partial_refund, null: false, foreign_key: true
      t.references :order_item, null: false, foreign_key: true
      t.integer :qty, null: false
      t.integer :amount_cents, null: false
      t.timestamps
    end
  end
end
