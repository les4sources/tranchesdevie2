class RefactorFloursWithRatios < ActiveRecord::Migration[8.0]
  # Valeurs de repli historiques (ex-DoughRatio globaux) si la table est vide.
  DEFAULTS = { "farine" => 0.5556, "eau" => 0.655, "sel" => 0.022, "levain" => 0.12095 }.freeze

  def up
    add_column :flours, :flour_ratio, :decimal, precision: 10, scale: 5, null: false, default: DEFAULTS["farine"]
    add_column :flours, :water_ratio, :decimal, precision: 10, scale: 5, null: false, default: DEFAULTS["eau"]
    add_column :flours, :salt_ratio, :decimal, precision: 10, scale: 5, null: false, default: DEFAULTS["sel"]
    add_column :flours, :levain_ratio, :decimal, precision: 10, scale: 5, null: false, default: DEFAULTS["levain"]
    add_column :flours, :levain_type, :string, null: false, default: "froment"
    add_column :flours, :origin, :string
    add_column :flours, :grade, :string
    add_column :flours, :notes, :text
    add_column :flours, :price_per_kg_cents, :integer

    # Reprise des ratios globaux existants comme valeurs par défaut de chaque farine.
    if table_exists?(:dough_ratios)
      ratios = select_all("SELECT key, value FROM dough_ratios").rows.to_h
      farine = (ratios["farine"] || DEFAULTS["farine"]).to_f
      eau    = (ratios["eau"]    || DEFAULTS["eau"]).to_f
      sel    = (ratios["sel"]    || DEFAULTS["sel"]).to_f
      levain = (ratios["levain"] || DEFAULTS["levain"]).to_f

      execute(sanitize_sql([
        "UPDATE flours SET flour_ratio = ?, water_ratio = ?, salt_ratio = ?, levain_ratio = ?",
        farine, eau, sel, levain
      ]))

      drop_table :dough_ratios
    end
  end

  def down
    create_table :dough_ratios do |t|
      t.string :key, null: false
      t.decimal :value, precision: 10, scale: 5, null: false
      t.string :label, null: false
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :dough_ratios, :key, unique: true

    remove_column :flours, :flour_ratio
    remove_column :flours, :water_ratio
    remove_column :flours, :salt_ratio
    remove_column :flours, :levain_ratio
    remove_column :flours, :levain_type
    remove_column :flours, :origin
    remove_column :flours, :grade
    remove_column :flours, :notes
    remove_column :flours, :price_per_kg_cents
  end

  private

  def sanitize_sql(array)
    ActiveRecord::Base.send(:sanitize_sql_array, array)
  end
end
