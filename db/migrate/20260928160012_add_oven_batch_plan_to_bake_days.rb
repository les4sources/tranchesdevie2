# Décision des boulangers quand le four approche de deux fournées pleines
# (alerte « Capacité four », Claire 28/09/2026) : rester à 2 fournées ou en
# ouvrir une 3e. NULL = pas encore décidé.
class AddOvenBatchPlanToBakeDays < ActiveRecord::Migration[8.1]
  def change
    add_column :bake_days, :oven_batch_plan, :integer
    add_column :bake_days, :oven_batch_plan_decided_at, :datetime
  end
end
