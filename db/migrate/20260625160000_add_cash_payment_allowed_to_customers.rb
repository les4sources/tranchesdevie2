class AddCashPaymentAllowedToCustomers < ActiveRecord::Migration[8.0]
  def change
    # Par défaut, les clients paient en ligne uniquement (#36). Ce réglage admin
    # ré-autorise le paiement hors-ligne (cash / facture) pour des clients
    # spécifiques (pros, points de dépôt, habitués).
    add_column :customers, :cash_payment_allowed, :boolean, default: false, null: false
  end
end
