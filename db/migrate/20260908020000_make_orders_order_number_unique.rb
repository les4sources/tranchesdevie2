# frozen_string_literal: true

# Unicité du numéro de commande au niveau de la base (#261).
#
# `Order` valide déjà `uniqueness: true` sur `order_number` et sérialise la
# génération avec un verrou consultatif, mais rien n'empêchait deux commandes de
# porter le même numéro si la validation était contournée (import, console,
# course non couverte). Puisque le numéro identifie la commande auprès de la
# cliente et des boulangers, la contrainte appartient à la base.
#
# `algorithm: :concurrently` (donc `disable_ddl_transaction!`) : la table est
# lue en permanence par la boutique, on ne la verrouille pas en écriture.
class MakeOrdersOrderNumberUnique < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    duplicates = select_rows(<<~SQL)
      SELECT order_number, COUNT(*)
      FROM orders
      GROUP BY order_number
      HAVING COUNT(*) > 1
      ORDER BY order_number
    SQL

    if duplicates.any?
      listing = duplicates.map { |number, count| "#{number} (#{count})" }.join(", ")
      raise ActiveRecord::MigrationError,
            "Impossible de créer l'index unique sur orders.order_number : " \
            "#{duplicates.size} numéro(s) en double — #{listing}. " \
            "Corrigez ces commandes (renumérotation ou suppression des doublons) puis relancez la migration."
    end

    remove_index :orders, column: :order_number, algorithm: :concurrently, if_exists: true
    add_index :orders, :order_number, unique: true, algorithm: :concurrently
  end

  def down
    remove_index :orders, column: :order_number, algorithm: :concurrently, if_exists: true
    add_index :orders, :order_number, algorithm: :concurrently
  end
end
