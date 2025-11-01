class CreateAdminPages < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_pages do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.text :body

      t.timestamps
    end

    add_index :admin_pages, :slug, unique: true
  end
end
