# Une party PUBLIQUE n'est pas toujours une Pizza Party : d'octobre à mars, la
# Camembert Party la remplace (#camembert-parties). Les convives y cuisent leur
# fromage, la boulangerie ne pétrit pas de pâtons mais fournit du pain — un
# grand froment 1 kg pour cinq personnes. La formule le dit à la production.
class AddMenuToPartyEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :party_events, :menu, :integer, null: false, default: 0

    # Les Camembert Parties déjà programmées le disent dans leur titre.
    execute <<~SQL.squish
      UPDATE party_events SET menu = 1
      WHERE kind = 0 AND title ILIKE '%camembert%'
    SQL
  end

  def down
    remove_column :party_events, :menu
  end
end
