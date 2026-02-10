class CreateCustomerGroups < ActiveRecord::Migration[8.0]
  def up
    create_table :customer_groups do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: true
      t.timestamps
    end
    add_index :customer_groups, [:customer_id, :group_id], unique: true, name: "idx_customer_groups_unique"

    # Migrate existing group_id data
    execute <<-SQL.squish
      INSERT INTO customer_groups (customer_id, group_id, created_at, updated_at)
      SELECT id, group_id, NOW(), NOW()
      FROM customers
      WHERE group_id IS NOT NULL
    SQL

    remove_reference :customers, :group, foreign_key: true
  end

  def down
    add_reference :customers, :group, null: true, foreign_key: true

    # Restore group_id from first group (arbitrary when customer had multiple)
    execute <<-SQL.squish
      UPDATE customers c
      SET group_id = (
        SELECT group_id FROM customer_groups
        WHERE customer_id = c.id
        ORDER BY created_at ASC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM customer_groups WHERE customer_id = c.id
      )
    SQL

    drop_table :customer_groups
  end
end
