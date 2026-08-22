class AddPizzaPartyToProducts < ActiveRecord::Migration[8.0]
  def change
    # Rôle d'un produit dans la "Pizza party privée" (#68) :
    #   none (0)    : produit normal
    #   party (1)   : le produit "Pizza party privée" (quantité = nombre de personnes)
    #   forfait (2) : le forfait 40 € (matériel + four à bois), ajouté une fois par commande
    add_column :products, :pizza_party_role, :integer, default: 0, null: false
  end
end
