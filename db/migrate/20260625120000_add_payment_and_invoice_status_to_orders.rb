class AddPaymentAndInvoiceStatusToOrders < ActiveRecord::Migration[8.0]
  def up
    # Nouveaux axes additifs (l'enum `status` logistique reste inchangé — cf. #41/#102).
    # payment_status : unpaid=0, paid=1, partially_paid=2 (réservé), refunded=3
    add_column :orders, :payment_status, :integer, default: 0, null: false
    # invoice_status : not_invoiced=0, invoiced=1
    add_column :orders, :invoice_status, :integer, default: 0, null: false
    add_index :orders, :payment_status

    # Backfill du payment_status depuis le paiement RÉEL (transactions), pas
    # depuis l'ancien `status` :
    #   - paid     : un paiement Stripe encaissé (payments.status = succeeded=0)
    #                OU un débit portefeuille (wallet_transactions.transaction_type = order_debit=1)
    #   - refunded : un paiement Stripe remboursé (payments.status = refunded=2)
    #                OU un remboursement portefeuille (transaction_type = order_refund=2)
    #     (refunded prime sur paid : il s'applique après).
    #   - unpaid   : aucun des deux (valeur par défaut).
    execute(<<~SQL.squish)
      UPDATE orders SET payment_status = 1
      WHERE id IN (
        SELECT order_id FROM payments WHERE status = 0
        UNION
        SELECT order_id FROM wallet_transactions WHERE transaction_type = 1 AND order_id IS NOT NULL
      )
    SQL

    execute(<<~SQL.squish)
      UPDATE orders SET payment_status = 3
      WHERE id IN (
        SELECT order_id FROM payments WHERE status = 2
        UNION
        SELECT order_id FROM wallet_transactions WHERE transaction_type = 2 AND order_id IS NOT NULL
      )
    SQL

    # invoice_status reste à not_invoiced (0) partout : c'est déjà la valeur par défaut.
  end

  def down
    remove_index :orders, :payment_status
    remove_column :orders, :payment_status
    remove_column :orders, :invoice_status
  end
end
