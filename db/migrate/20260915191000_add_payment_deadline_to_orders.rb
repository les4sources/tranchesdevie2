class AddPaymentDeadlineToOrders < ActiveRecord::Migration[8.0]
  def change
    # Échéance de paiement d'une réservation de Pizza party validée
    # (#pizza-parties) : passé ce terme, la commande est annulée et le créneau
    # rendu. Nul pour toute autre commande.
    add_column :orders, :payment_due_at, :datetime
    # Horodatages d'envoi des deux e-mails datés (sollicitation J-5, relance
    # J-4) : leur présence EST la garde d'idempotence des jobs.
    add_column :orders, :payment_prompted_at, :datetime
    add_column :orders, :payment_reminded_at, :datetime

    add_index :orders, :payment_due_at, where: "payment_due_at IS NOT NULL"
  end
end
