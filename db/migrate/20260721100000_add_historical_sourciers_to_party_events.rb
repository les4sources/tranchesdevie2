# Boules « sourciers » (#pizza-parties) : non payantes sur BilletWeb, mais produites
# par les boulangers. Barème confirmé par Michael : 2 €/boule, intégralement aux
# boulangers. Stocké en agrégé sur l'événement historique.
class AddHistoricalSourciersToPartyEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :party_events, :historical_sourciers, :integer
  end
end
