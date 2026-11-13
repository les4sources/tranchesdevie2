# Fournée qui cuit les pains d'une Camembert Party. Ces pains sont des lignes
# CALCULÉES (aucun OrderItem enregistré), leur affectation à une fournée vit
# donc sur l'événement. Supprimer la fournée remet les pains en non affectés.
class AddBreadBatchToPartyEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :party_events, :bread_batch, foreign_key: { to_table: :batches, on_delete: :nullify }, null: true
  end
end
