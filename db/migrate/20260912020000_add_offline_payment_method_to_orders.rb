# Moyen d'encaissement HORS-LIGNE pointé par le boulanger au moment de la remise
# (#275) : cash ou virement. Nullable et sans défaut — une commande non pointée
# reste non pointée, et le déploiement ne touche aucune commande existante.
class AddOfflinePaymentMethodToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :offline_payment_method, :integer
  end
end
