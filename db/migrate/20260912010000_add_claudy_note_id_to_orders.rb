# Identifiant de la note posée sur le calendrier de claudy pour une Pizza party
# privée (#259). Nullable : la très grande majorité des commandes n'en a pas.
class AddClaudyNoteIdToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :claudy_note_id, :bigint
  end
end
