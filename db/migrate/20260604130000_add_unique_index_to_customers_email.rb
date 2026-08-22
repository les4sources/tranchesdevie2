class AddUniqueIndexToCustomersEmail < ActiveRecord::Migration[8.0]
  def change
    # Index fonctionnel insensible à la casse, partiel : on n'impose l'unicité
    # qu'aux adresses réellement renseignées (NULL et chaîne vide sont exclus,
    # 35 clients sur 97 au moment de la création).
    add_index :customers, "lower(email)",
              unique: true,
              name: "index_customers_on_lower_email_unique",
              where: "email IS NOT NULL AND email <> ''"
  end
end
