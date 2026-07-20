# Historique BilletWeb (#pizza-parties) : avant le passage 100 % par le site, les
# pizza parties publiques étaient vendues via BilletWeb et l'argent arrivait
# intégralement sur le compte de la fondation Les 4 Sources. On stocke ces ventes
# en AGRÉGÉ sur l'événement (pas de commandes ni de fiches clients) pour que le
# reporting applique rétroactivement le barème public et calcule la part due aux
# boulangers. Colonnes nullables : renseignées uniquement pour les événements importés.
class AddHistoricalBilletwebToPartyEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :party_events, :historical_source, :string
    add_column :party_events, :historical_adults, :integer
    add_column :party_events, :historical_children, :integer
    add_column :party_events, :historical_fees_cents, :integer
  end
end
