class AddDraftToBakeDays < ActiveRecord::Migration[8.0]
  def change
    # Jour de cuisson « brouillon » (#197) : les boulangers s'en servent comme
    # d'une calculatrice (panification, moules, pâtons de pizza party) sans que
    # le jour existe commercialement. `default: false` : tous les jours déjà en
    # base restent comptabilisés.
    add_column :bake_days, :draft, :boolean, default: false, null: false
    add_index :bake_days, :draft
  end
end
