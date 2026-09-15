class MakePartyRequestPersonsOptional < ActiveRecord::Migration[8.0]
  def change
    # Le nombre de participants n'est plus demandé à la demande : il n'est pas
    # nécessaire pour décider, et le client l'arrête au paiement, une fois qu'il
    # sait vraiment qui vient (#pizza-parties).
    change_column_null :party_requests, :estimated_persons, true
  end
end
