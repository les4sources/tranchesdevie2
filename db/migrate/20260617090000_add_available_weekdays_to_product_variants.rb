class AddAvailableWeekdaysToProductVariants < ActiveRecord::Migration[8.0]
  def change
    # Liste des jours de cuisson (wday : 0=dimanche … 6=samedi) où la variante est
    # disponible. Tableau vide = disponible tous les jours de cuisson (comportement
    # historique : aucune variante existante n'est restreinte après la migration).
    add_column :product_variants, :available_weekdays, :integer, array: true, default: [], null: false
  end
end
