class AddPartyRequestToEmailMessages < ActiveRecord::Migration[8.0]
  def change
    # Les e-mails du parcours Pizza party qui PRÉCÈDENT la validation n'ont pas
    # d'`order_id` (la commande n'existe pas encore) : leur idempotence se garde
    # sur la demande (#pizza-parties).
    add_reference :email_messages, :party_request, foreign_key: true, null: true
  end
end
