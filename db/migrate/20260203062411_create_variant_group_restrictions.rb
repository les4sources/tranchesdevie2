class CreateVariantGroupRestrictions < ActiveRecord::Migration[8.0]
  def change
    create_table :variant_group_restrictions do |t|
      t.references :product_variant, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: true

      t.timestamps
    end

    add_index :variant_group_restrictions, [:product_variant_id, :group_id],
              unique: true, name: "idx_variant_group_restrictions_unique"
  end
end
