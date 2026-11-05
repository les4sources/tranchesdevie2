# Structure juridique d'un client facturable (retour Michael 05/11/2026) : le
# client paie avec sa structure (« SRL Les Délices de Godinne »), dont le nom
# diffère souvent de sa dénomination commerciale, qui reste son nom de client.
# Facultatif, purement informatif : sert à reconnaître le payeur en Facturation.
class AddLegalNameToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :legal_name, :string
  end
end
