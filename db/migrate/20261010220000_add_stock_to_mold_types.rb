# frozen_string_literal: true

# Nombre de moules physiquement présents dans l'armoire, par type. Distinct de
# `limit` (unités vendables sur un jour de cuisson) : un moule ressert après
# chaque fournée, mais tant qu'une fournée cuit, la suivante lève déjà dans ses
# moules. D'où la contrainte « deux fournées consécutives ne dépassent pas le
# stock » de la proposition de répartition (Michael, 10/10/2026).
class AddStockToMoldTypes < ActiveRecord::Migration[8.0]
  STOCKS = {
    "Grand" => 95,
    "Classique" => 38,
    "Petit" => 80,
    "Classique rond" => 10
  }.freeze

  def up
    add_column :mold_types, :stock, :integer

    STOCKS.each do |name, stock|
      execute(<<-SQL.squish)
        UPDATE mold_types SET stock = #{stock}
        WHERE name = #{connection.quote(name)} AND deleted_at IS NULL
      SQL
    end
  end

  def down
    remove_column :mold_types, :stock
  end
end
