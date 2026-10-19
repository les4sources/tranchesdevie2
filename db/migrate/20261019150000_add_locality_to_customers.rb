# Village / commune déclaré par le client (retour Michael 19/10/2026) : savoir
# d'où viennent nos mangeurs. Facultatif ; jamais l'adresse. La date de refus
# évite de reposer la question à qui a préféré ne pas répondre.
class AddLocalityToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :locality, :string
    add_column :customers, :locality_prompt_dismissed_at, :datetime
    add_index :customers, "lower(locality)", name: "index_customers_on_lower_locality"
  end
end
