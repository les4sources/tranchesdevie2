class AddInternalNoteToBakeDays < ActiveRecord::Migration[8.0]
  def change
    add_column :bake_days, :internal_note, :text
  end
end


